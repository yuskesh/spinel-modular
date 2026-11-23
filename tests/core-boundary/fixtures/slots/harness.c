/* The C driver for tests/core-boundary/slots.sh, and for the adapter lane in
 * tests/core-boundary/artifacts.sh.
 *
 * It MODELS NOTHING. Every result and every cell it compares against is
 * written in trace.tsv; this file parses the trace, calls the CORE kernels and
 * compares.
 *
 *   usage: harness <trace-file> <mode>
 *
 *     run     execute the trace's operations in order on one world. Each must
 *             answer SPINEL_CORE_OK and the result the trace records, and
 *             each `expect` line must match the named array cell for cell at
 *             the point where it stands.
 *     refuse  run the trace's checks, each on a fresh world with its own
 *             preloaded cells. Each must return the status the trace says.
 *
 * Exit 0 when the mode's expectation held, 1 otherwise.
 *
 * TWO BACK ENDS, ONE COMPARISON. Built plainly it calls the CORE entries
 * directly, on its own arrays, which is how a C consumer uses them. Built
 * with -DSPINEL_VIA_ADAPTER the same modes run through the Full adapter: the
 * arrays become registry storage, a call is an `invoke` over their ids, and
 * the cells are read back one at a time before a comparison. They are one
 * file so that the parsing and the comparison are the same source either way.
 *
 * WHAT THE TWO DO NOT SHARE. After a refusal a direct caller can still read
 * its arrays, including the cells the call wrote before it stopped: a check
 * declares how many, and the count is taken from the cells. Through the
 * adapter a refusal poisons the storage the call could write, and that is
 * what is checked there instead.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef SPINEL_VIA_ADAPTER
#include "spinel_adapter_queue_drop.h"
#include "spinel_adapter_queue_put.h"
#include "spinel_adapter_queue_take.h"
#include "spinel_adapter_slot_give.h"
#include "spinel_adapter_slot_take.h"
#include "spinel_adapter_registry.h"
#else
#include "spinel_core_queue_drop.h"
#include "spinel_core_queue_put.h"
#include "spinel_core_queue_take.h"
#include "spinel_core_slot_give.h"
#include "spinel_core_slot_take.h"
#endif

#define MAX_LINES 256
#define MAX_PRE 8
#define MAX_CAP 64

enum { K_SLOT_TAKE, K_SLOT_GIVE, K_QUEUE_PUT, K_QUEUE_TAKE, K_QUEUE_DROP, N_KERNELS };
enum { A_LINK, A_STATE, A_VALS, A_NXT, A_Q, N_ARRAYS };

static const char *const kernel_names[N_KERNELS] = {
  "slot_take", "slot_give", "queue_put", "queue_take", "queue_drop"};
static const char *const array_names[N_ARRAYS] = {"link", "state", "vals", "nxt", "q"};

#ifdef SPINEL_VIA_ADAPTER
/* The arrays each kernel is handed, which are the ones a refusal can have
 * written (every buffer here is inout). */
static const int kernel_arrays[N_KERNELS][N_ARRAYS] = {
  /* link state vals nxt q */
  {1, 1, 0, 0, 0},   /* slot_take */
  {1, 1, 0, 0, 0},   /* slot_give */
  {0, 0, 1, 1, 1},   /* queue_put */
  {0, 0, 0, 1, 1},   /* queue_take */
  {0, 0, 1, 1, 1},   /* queue_drop */
};
#endif

struct line {
  int is_expect;           /* 0: an operation, 1: an expectation */
  int kernel;
  int64_t a, b, result;
  int array;
  int32_t cells[MAX_CAP];
  size_t n_cells;
};

struct check {
  char id[40];
  int kernel;
  int64_t a, b;
  int shorten;             /* an array declared one cell short, or -1 */
  int32_t status;
  long moved;              /* refusals: cells the call wrote before it stopped */
  int has_result;
  int64_t result;
  int n_pre;
  struct { int array; long idx; long val; } pre[MAX_PRE];
};

struct world {
  int32_t *cells[N_ARRAYS];
  size_t n[N_ARRAYS];
#ifdef SPINEL_VIA_ADAPTER
  int32_t id[N_ARRAYS];
#endif
};

static size_t cap;
static struct line lines[MAX_LINES];
static size_t n_lines;
static struct check checks[MAX_LINES];
static size_t n_checks;

static void fail(const char *what) {
  fprintf(stderr, "harness: %s\n", what);
  exit(1);
}

static int find(const char *const *names, int n, const char *s) {
  for (int i = 0; i < n; i++)
    if (strcmp(names[i], s) == 0) return i;
  return -1;
}

static int64_t number(const char *s) {
  char *end;
  long long v = strtoll(s, &end, 10);
  if (end == s || *end != '\0') fail("a field that should be a number is not one");
  return (int64_t)v;
}

/* A fresh world: an empty pool and an empty queue. */
static void world_init(struct world *w) {
  static const int32_t fill[N_ARRAYS] = {-1, 0, -1, -1, 0};
  memset(w, 0, sizeof(*w));
  w->n[A_LINK] = w->n[A_VALS] = w->n[A_NXT] = cap;
  w->n[A_STATE] = 2;
  w->n[A_Q] = 3;
  for (int a = 0; a < N_ARRAYS; a++) {
    /* One spare cell, so a declaration one short still names real memory. */
    w->cells[a] = malloc((w->n[a] + 1) * sizeof(int32_t));
    if (!w->cells[a]) fail("out of memory");
    for (size_t i = 0; i <= w->n[a]; i++) w->cells[a][i] = fill[a];
  }
  w->cells[A_STATE][0] = -1;   /* nothing given back */
  w->cells[A_STATE][1] = 0;    /* no slot used yet */
  w->cells[A_Q][0] = -1;       /* no oldest */
  w->cells[A_Q][1] = -1;       /* no newest */
  w->cells[A_Q][2] = 0;        /* length */
}

static void world_free(struct world *w) {
  for (int a = 0; a < N_ARRAYS; a++) free(w->cells[a]);
}

#ifdef SPINEL_VIA_ADAPTER
enum { ELEM_I32 = 2, ELEM_U32 = 3, ELEM_I64 = 4 };
static int32_t id_result, id_words;

static void world_open(struct world *w) {
  static int started;
  if (!started) {
    if (spinel_adapter_registry_startup() != 0) fail("the adapter would not start");
    id_result = spinel_adapter_registry_allocate(ELEM_I64, 1);
    id_words = spinel_adapter_registry_allocate(ELEM_U32, 2);
    if (id_result <= 0 || id_words <= 0) fail("the adapter would not allocate a result");
    started = 1;
  }
  for (int a = 0; a < N_ARRAYS; a++) {
    w->id[a] = spinel_adapter_registry_allocate(ELEM_I32, (int64_t)w->n[a]);
    if (w->id[a] <= 0) fail("the adapter would not allocate storage");
    for (size_t i = 0; i < w->n[a]; i++)
      if (spinel_adapter_registry_store(w->id[a], (int64_t)i, (int64_t)w->cells[a][i]) != 0)
        fail("the adapter would not store into storage it had just made");
  }
}

static void world_close(struct world *w) {
  for (int a = 0; a < N_ARRAYS; a++)
    if (spinel_adapter_registry_release(w->id[a]) != 0) fail("the adapter would not release");
}

/* Reads one array back. Answers 1 when the storage is poisoned. */
static int array_back(struct world *w, int a) {
  for (size_t i = 0; i < w->n[a]; i++) {
    int64_t v = spinel_adapter_registry_load(w->id[a], (int64_t)i);
    if (v < 0) return 1;
    w->cells[a][i] = (int32_t)(v >= 2147483648LL ? v - 4294967296LL : v);
  }
  return 0;
}

/* The result cell is poisoned before every invoke, so "answered OK and wrote
 * nothing" and "refused and wrote anyway" are both visible. */
#define RESULT_POISON_LO 3735928559u   /* 0xdeadbeef */
#define RESULT_POISON_HI 3405691582u   /* 0xcafebabe */

static int32_t call_kernel(int kernel, int64_t a, int64_t b, struct world *w, int64_t *result) {
  int32_t st;
  if (spinel_adapter_registry_store_i64_words(id_result, 0, RESULT_POISON_LO,
                                              RESULT_POISON_HI) != 0)
    fail("the adapter would not poison the result cell");
  switch (kernel) {
    case K_SLOT_TAKE:
      st = spinel_adapter_slot_take_invoke(w->id[A_LINK], w->id[A_STATE], id_result);
      break;
    case K_SLOT_GIVE:
      st = spinel_adapter_slot_give_invoke(a, w->id[A_LINK], w->id[A_STATE], id_result);
      break;
    case K_QUEUE_PUT:
      st = spinel_adapter_queue_put_invoke(a, b, w->id[A_VALS], w->id[A_NXT], w->id[A_Q],
                                           id_result);
      break;
    case K_QUEUE_TAKE:
      st = spinel_adapter_queue_take_invoke(w->id[A_NXT], w->id[A_Q], id_result);
      break;
    default:
      st = spinel_adapter_queue_drop_invoke(a, w->id[A_VALS], w->id[A_NXT], w->id[A_Q],
                                            id_result);
      break;
  }
  /* i64 storage refuses the ordinary load on purpose; the result comes back
   * as two unsigned words. */
  if (spinel_adapter_registry_load_i64_words(id_result, 0, id_words, 0, 1) != 0)
    fail("the adapter would not read back the result cell");
  int64_t lo = spinel_adapter_registry_load(id_words, 0);
  int64_t hi = spinel_adapter_registry_load(id_words, 1);
  if (lo < 0 || hi < 0) fail("the adapter would not read back a result word");
  int64_t got = (int64_t)(((uint64_t)hi << 32) | (uint64_t)lo);
  const int64_t poison = (int64_t)(((uint64_t)RESULT_POISON_HI << 32) |
                                   (uint64_t)RESULT_POISON_LO);
  if (st == SPINEL_CORE_OK) {
    if (got == poison) fail("an accepted invoke wrote no result");
    *result = got;
  } else if (got != poison) {
    fail("a refused invoke wrote a result");
  }
  return st;
}
#else
#define world_open(w) ((void)(w))
#define world_close(w) ((void)(w))
/* The direct build works on its own arrays; there is nothing to bring back. */
#define array_back(w, a) ((void)(w), (void)(a), 0)

static int32_t call_kernel(int kernel, int64_t a, int64_t b, struct world *w, int64_t *result) {
  switch (kernel) {
    case K_SLOT_TAKE:
      return spinel_core_slot_take(w->cells[A_LINK], w->n[A_LINK], w->cells[A_STATE],
                                   w->n[A_STATE], result);
    case K_SLOT_GIVE:
      return spinel_core_slot_give(a, w->cells[A_LINK], w->n[A_LINK], w->cells[A_STATE],
                                   w->n[A_STATE], result);
    case K_QUEUE_PUT:
      return spinel_core_queue_put(a, b, w->cells[A_VALS], w->n[A_VALS], w->cells[A_NXT],
                                   w->n[A_NXT], w->cells[A_Q], w->n[A_Q], result);
    case K_QUEUE_TAKE:
      return spinel_core_queue_take(w->cells[A_NXT], w->n[A_NXT], w->cells[A_Q], w->n[A_Q],
                                    result);
    default:
      return spinel_core_queue_drop(a, w->cells[A_VALS], w->n[A_VALS], w->cells[A_NXT],
                                    w->n[A_NXT], w->cells[A_Q], w->n[A_Q], result);
  }
}
#endif

/* Splits a line on tabs in place; answers the number of fields. */
static int fields(char *line, char **out, int max) {
  int n = 0;
  char *p = line;
  while (n < max) {
    out[n++] = p;
    char *tab = strchr(p, '\t');
    if (!tab) break;
    *tab = '\0';
    p = tab + 1;
  }
  return n;
}

static void parse(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) fail("the trace file will not open");
  char buf[1024];
  while (fgets(buf, sizeof(buf), f)) {
    size_t len = strlen(buf);
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r')) buf[--len] = '\0';
    if (len == 0 || buf[0] == '#') continue;
    char *fv[12];
    int nf = fields(buf, fv, 12);
    if (strcmp(fv[0], "cap") == 0 && nf == 2) {
      cap = (size_t)number(fv[1]);
      if (cap == 0 || cap > MAX_CAP - 1) fail("the capacity is out of the harness's range");
    } else if (strcmp(fv[0], "op") == 0 && nf == 5) {
      if (n_lines == MAX_LINES) fail("too many trace lines");
      struct line *l = &lines[n_lines++];
      memset(l, 0, sizeof(*l));
      l->kernel = find(kernel_names, N_KERNELS, fv[1]);
      if (l->kernel < 0) fail("an operation names no kernel");
      l->a = strcmp(fv[2], "-") == 0 ? 0 : number(fv[2]);
      l->b = strcmp(fv[3], "-") == 0 ? 0 : number(fv[3]);
      l->result = number(fv[4]);
    } else if (strcmp(fv[0], "expect") == 0 && nf == 3) {
      if (n_lines == MAX_LINES) fail("too many trace lines");
      struct line *l = &lines[n_lines++];
      memset(l, 0, sizeof(*l));
      l->is_expect = 1;
      l->array = find(array_names, N_ARRAYS, fv[1]);
      if (l->array < 0) fail("an expectation names no array");
      for (char *tok = strtok(fv[2], ","); tok; tok = strtok(NULL, ",")) {
        if (l->n_cells == MAX_CAP) fail("an expectation is too long");
        l->cells[l->n_cells++] = (int32_t)number(tok);
      }
    } else if (strcmp(fv[0], "check") == 0 && nf == 10) {
      if (n_checks == MAX_LINES) fail("too many checks");
      struct check *c = &checks[n_checks++];
      memset(c, 0, sizeof(*c));
      snprintf(c->id, sizeof(c->id), "%s", fv[1]);
      c->kernel = find(kernel_names, N_KERNELS, fv[2]);
      if (c->kernel < 0) fail("a check names no kernel");
      c->a = strcmp(fv[3], "-") == 0 ? 0 : number(fv[3]);
      c->b = strcmp(fv[4], "-") == 0 ? 0 : number(fv[4]);
      c->shorten = strcmp(fv[5], "-") == 0 ? -1 : find(array_names, N_ARRAYS, fv[5]);
      if (strcmp(fv[5], "-") != 0 && c->shorten < 0) fail("a check shortens no array");
      c->status = (int32_t)number(fv[6]);
      c->moved = strcmp(fv[7], "-") == 0 ? 0 : (long)number(fv[7]);
      c->has_result = strcmp(fv[8], "-") != 0;
      if (c->has_result) c->result = number(fv[8]);
      if (strcmp(fv[9], "-") != 0) {
        /* preloads: array:index=value, space-separated */
        for (char *tok = strtok(fv[9], " "); tok; tok = strtok(NULL, " ")) {
          if (c->n_pre == MAX_PRE) fail("a check preloads too many cells");
          char *colon = strchr(tok, ':'), *eq = strchr(tok, '=');
          if (!colon || !eq || eq < colon) fail("a preload is not array:index=value");
          *colon = '\0';
          *eq = '\0';
          int a = find(array_names, N_ARRAYS, tok);
          if (a < 0) fail("a preload names no array");
          c->pre[c->n_pre].array = a;
          c->pre[c->n_pre].idx = (long)number(colon + 1);
          c->pre[c->n_pre].val = (long)number(eq + 1);
          c->n_pre++;
        }
      }
    } else {
      fail("a trace line is of no known kind");
    }
  }
  fclose(f);
  if (cap == 0) fail("the trace names no capacity");
}

static int mode_run(void) {
  struct world w;
  long n_ops = 0, n_expect = 0;
  int reached[N_KERNELS] = {0};
  world_init(&w);
  world_open(&w);
  for (size_t i = 0; i < n_lines; i++) {
    const struct line *l = &lines[i];
    if (!l->is_expect) {
      int64_t result = 0;
      int32_t st = call_kernel(l->kernel, l->a, l->b, &w, &result);
      n_ops++;
      reached[l->kernel] = 1;
      if (st != SPINEL_CORE_OK) {
        fprintf(stderr, "harness: operation %ld (%s) answered status %d\n", n_ops,
                kernel_names[l->kernel], (int)st);
        return 1;
      }
      if (result != l->result) {
        fprintf(stderr, "harness: operation %ld (%s) answered %lld, the trace says %lld\n",
                n_ops, kernel_names[l->kernel], (long long)result, (long long)l->result);
        return 1;
      }
    } else {
      n_expect++;
      if (array_back(&w, l->array)) fail("an accepted operation poisoned its storage");
      if (l->n_cells != w.n[l->array]) fail("an expectation is not the array's length");
      for (size_t k = 0; k < l->n_cells; k++) {
        if (w.cells[l->array][k] != l->cells[k]) {
          fprintf(stderr, "harness: after operation %ld, %s[%zu] is %d, the trace says %d\n",
                  n_ops, array_names[l->array], k, (int)w.cells[l->array][k], (int)l->cells[k]);
          return 1;
        }
      }
    }
  }
  world_close(&w);
  world_free(&w);
  /* A trace that would pass for the wrong reason is refused. */
  if (n_ops == 0 || n_expect == 0) fail("the trace has no operation or no expectation");
  for (int k = 0; k < N_KERNELS; k++)
    if (!reached[k]) fail("the trace never reaches one of the kernels");
  printf("run: %ld operation(s), %ld expectation(s)\n", n_ops, n_expect);
  return 0;
}

static int mode_refuse(void) {
  long refusals = 0, bounds = 0, capacity = 0;
  int reached[N_KERNELS] = {0};
  for (size_t i = 0; i < n_checks; i++) {
    const struct check *c = &checks[i];
    struct world w;
    world_init(&w);
    for (int p = 0; p < c->n_pre; p++) {
      int a = c->pre[p].array;
      if (c->pre[p].idx < 0 || (size_t)c->pre[p].idx >= w.n[a]) fail("a preload is off its array");
      w.cells[a][c->pre[p].idx] = (int32_t)c->pre[p].val;
    }
    if (c->shorten >= 0) w.n[c->shorten]--;
    int32_t *before[N_ARRAYS];
    for (int a = 0; a < N_ARRAYS; a++) {
      before[a] = malloc((w.n[a] + 1) * sizeof(int32_t));
      if (!before[a]) fail("out of memory");
      memcpy(before[a], w.cells[a], w.n[a] * sizeof(int32_t));
    }
    world_open(&w);
    int64_t result = 0;
    int32_t st = call_kernel(c->kernel, c->a, c->b, &w, &result);
    reached[c->kernel] = 1;
    if (st != c->status) {
      fprintf(stderr, "harness: check %s answered status %d, the trace says %d\n", c->id,
              (int)st, (int)c->status);
      return 1;
    }
    if (st == SPINEL_CORE_OK) {
      if (c->has_result && result != c->result) {
        fprintf(stderr, "harness: check %s answered %lld, the trace says %lld\n", c->id,
                (long long)result, (long long)c->result);
        return 1;
      }
      for (int a = 0; a < N_ARRAYS; a++)
        if (array_back(&w, a)) fail("an accepted call poisoned its storage");
    } else {
      refusals++;
      if (st == SPINEL_CORE_BOUNDS) bounds++;
      if (st == SPINEL_CORE_CAPACITY) capacity++;
#ifdef SPINEL_VIA_ADAPTER
      /* A refusal poisons every array the call could write, and no other. */
      for (int a = 0; a < N_ARRAYS; a++) {
        int poisoned = array_back(&w, a);
        if (poisoned != kernel_arrays[c->kernel][a]) {
          fprintf(stderr, "harness: check %s: after the refusal `%s` is %s\n", c->id,
                  array_names[a], poisoned ? "poisoned" : "not poisoned");
          return 1;
        }
      }
#else
      /* What a direct caller can still read: the cells the call wrote before
       * it stopped, counted from the arrays and not from the trace. */
      long changed = 0;
      for (int a = 0; a < N_ARRAYS; a++)
        for (size_t k = 0; k < w.n[a]; k++)
          if (w.cells[a][k] != before[a][k]) changed++;
      if (changed != c->moved) {
        fprintf(stderr, "harness: check %s changed %ld cell(s), and declares %ld\n", c->id,
                changed, c->moved);
        return 1;
      }
#endif
    }
    world_close(&w);
    for (int a = 0; a < N_ARRAYS; a++) free(before[a]);
    world_free(&w);
  }
  /* The checks have to ask the questions they are there for. */
  if (bounds == 0 || capacity == 0) fail("the checks never refuse with both statuses");
  if (refusals == (long)n_checks) fail("no check is accepted, so no edge has its inside");
  for (int k = 0; k < N_KERNELS; k++)
    if (!reached[k]) fail("the checks never reach one of the kernels");
  printf("refuse: %zu check(s), %ld refusal(s)\n", n_checks, refusals);
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 3) fail("usage: harness <trace-file> <run|refuse>");
  parse(argv[1]);
  if (strcmp(argv[2], "run") == 0) return mode_run();
  if (strcmp(argv[2], "refuse") == 0) return mode_refuse();
  fail("unknown mode; expected run or refuse");
  return 2;
}
