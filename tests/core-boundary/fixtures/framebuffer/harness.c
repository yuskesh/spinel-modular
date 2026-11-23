/* The C driver for tests/core-boundary/framebuffer.sh, and for the adapter
 * lane in tests/core-boundary/artifacts.sh.
 *
 * It DRAWS NOTHING. The screen it compares against is written in scene.tsv;
 * this file parses the scene, calls the CORE kernels over its jobs and
 * compares every byte of the screen, including the bytes no job touches.
 *
 *   usage: harness <scene-file> <mode>
 *
 *     run      execute the jobs in order; every byte must match.
 *     reverse  execute them backwards; the screen must DIFFER. Without this,
 *              "the order is preserved" would be a claim about a scene whose
 *              order did not matter, and col_smear's read of what earlier
 *              jobs drew would be unobservable.
 *     refuse   run the scene's checks, each against a fresh screen; each
 *              must return the status the scene says.
 *
 * Exit 0 when the mode's expectation held, 1 otherwise.
 *
 * TWO BACK ENDS, ONE COMPARISON. Built plainly it calls the CORE entries
 * directly, which is how a C consumer uses them. Built with
 * -DSPINEL_VIA_ADAPTER the same modes run through the Full adapter: the
 * screen and the tables become registry storage, a job is an `invoke` over
 * their ids, and the screen is read back a cell at a time before the
 * comparison. They are one file so that the parsing and the byte comparison
 * are the same source either way.
 *
 * WHAT THE TWO DO NOT SHARE. After a refusal a direct caller can still read
 * its screen, including the pixels the call drew before it stopped: a check
 * declares how many, and the count is taken from the screen. Through the
 * adapter a refusal poisons the screen, the one buffer a kernel can write,
 * and leaves the tables it only reads; that is what is checked there.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef SPINEL_VIA_ADAPTER
#include "spinel_adapter_col_fill.h"
#include "spinel_adapter_col_smear.h"
#include "spinel_adapter_row_fill.h"
#include "spinel_adapter_registry.h"
#else
#include "spinel_core_col_fill.h"
#include "spinel_core_col_smear.h"
#include "spinel_core_row_fill.h"
#endif

#define MAX_JOBS 64
#define MAX_CELLS 4096
#define N_FIELDS 7

enum { K_COL, K_ROW, K_SMEAR, N_KERNELS };
enum { T_PAT, T_TILE, T_LUT, T_OFFS, N_TABLES };   /* T_OFFS is i32, the rest u8 */

static const char *const kernel_names[N_KERNELS] = {"col", "row", "smear"};
static const char *const table_names[N_TABLES] = {"pat", "tile", "lut", "offs"};

struct job {
  int kernel;
  int64_t f[N_FIELDS];
};

struct check {
  char id[40];
  struct job job;
  int shorten;             /* a table declared one cell short, or -1 */
  int32_t status;
  long moved;              /* refusals: pixels drawn before the call stopped */
};

static int64_t width, height;
static uint8_t expect[MAX_CELLS];
static size_t n_expect;
static int32_t table[N_TABLES][MAX_CELLS];
static size_t n_table[N_TABLES];
static struct job jobs[MAX_JOBS];
static size_t n_jobs;
static struct check checks[MAX_JOBS];
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

/* The buffers one call sees: the screen, and each table as the element type
 * its kernel declares, with the count the caller declares for it. */
struct view {
  uint8_t *scr;
  size_t n_scr;
  uint8_t pat[MAX_CELLS], tile[MAX_CELLS], lut[MAX_CELLS];
  int32_t offs[MAX_CELLS];
  size_t n[N_TABLES];
#ifdef SPINEL_VIA_ADAPTER
  int32_t id_scr, id[N_TABLES];
#endif
};

static void view_init(struct view *v, uint8_t *scr, int shorten) {
  v->scr = scr;
  v->n_scr = (size_t)(width * height);
  for (int t = 0; t < N_TABLES; t++) v->n[t] = n_table[t];
  for (size_t i = 0; i < n_table[T_PAT]; i++) v->pat[i] = (uint8_t)table[T_PAT][i];
  for (size_t i = 0; i < n_table[T_TILE]; i++) v->tile[i] = (uint8_t)table[T_TILE][i];
  for (size_t i = 0; i < n_table[T_LUT]; i++) v->lut[i] = (uint8_t)table[T_LUT][i];
  for (size_t i = 0; i < n_table[T_OFFS]; i++) v->offs[i] = table[T_OFFS][i];
  if (shorten >= 0) v->n[shorten]--;
}

#ifdef SPINEL_VIA_ADAPTER
enum { ELEM_U8 = 1, ELEM_I32 = 2, ELEM_U32 = 3, ELEM_I64 = 4 };
static int32_t id_result, id_words;

static int32_t put(int32_t element, size_t n) {
  int32_t id = spinel_adapter_registry_allocate(element, (int64_t)n);
  if (id <= 0) fail("the adapter would not allocate storage");
  return id;
}

static void store(int32_t id, size_t i, int64_t value) {
  if (spinel_adapter_registry_store(id, (int64_t)i, value) != 0)
    fail("the adapter would not store into storage it had just made");
}

static void view_open(struct view *v) {
  static int started;
  if (!started) {
    if (spinel_adapter_registry_startup() != 0) fail("the adapter would not start");
    id_result = put(ELEM_I64, 1);
    id_words = put(ELEM_U32, 2);
    started = 1;
  }
  v->id_scr = put(ELEM_U8, v->n_scr);
  for (size_t i = 0; i < v->n_scr; i++) store(v->id_scr, i, v->scr[i]);
  v->id[T_PAT] = put(ELEM_U8, v->n[T_PAT]);
  for (size_t i = 0; i < v->n[T_PAT]; i++) store(v->id[T_PAT], i, v->pat[i]);
  v->id[T_TILE] = put(ELEM_U8, v->n[T_TILE]);
  for (size_t i = 0; i < v->n[T_TILE]; i++) store(v->id[T_TILE], i, v->tile[i]);
  v->id[T_LUT] = put(ELEM_U8, v->n[T_LUT]);
  for (size_t i = 0; i < v->n[T_LUT]; i++) store(v->id[T_LUT], i, v->lut[i]);
  v->id[T_OFFS] = put(ELEM_I32, v->n[T_OFFS]);
  for (size_t i = 0; i < v->n[T_OFFS]; i++) store(v->id[T_OFFS], i, v->offs[i]);
}

/* Reads the screen back. Answers 1 when it is poisoned. */
static int screen_back(struct view *v) {
  for (size_t i = 0; i < v->n_scr; i++) {
    int64_t c = spinel_adapter_registry_load(v->id_scr, (int64_t)i);
    if (c < 0) return 1;
    v->scr[i] = (uint8_t)c;
  }
  return 0;
}

/* Whether any table is poisoned: a refusal must leave what it only read. */
static int tables_poisoned(const struct view *v) {
  for (int t = 0; t < N_TABLES; t++)
    if (v->n[t] > 0 && spinel_adapter_registry_load(v->id[t], 0) < 0) return 1;
  return 0;
}

static void view_close(struct view *v) {
  if (spinel_adapter_registry_release(v->id_scr) != 0) fail("the adapter would not release");
  for (int t = 0; t < N_TABLES; t++)
    if (spinel_adapter_registry_release(v->id[t]) != 0) fail("the adapter would not release");
}

/* The result cell is poisoned before every invoke, so "answered OK and wrote
 * nothing" and "refused and wrote anyway" are both visible. */
#define RESULT_POISON_LO 3735928559u   /* 0xdeadbeef */
#define RESULT_POISON_HI 3405691582u   /* 0xcafebabe */

static int32_t call_kernel(const struct job *j, struct view *v) {
  const int64_t *f = j->f;
  int32_t st;
  if (spinel_adapter_registry_store_i64_words(id_result, 0, RESULT_POISON_LO,
                                              RESULT_POISON_HI) != 0)
    fail("the adapter would not poison the result cell");
  switch (j->kernel) {
    case K_COL:
      st = spinel_adapter_col_fill_invoke(v->id_scr, v->id[T_PAT], v->id[T_LUT], f[0], f[1],
                                          f[2], f[3], f[4], f[5], f[6], width, id_result);
      break;
    case K_ROW:
      st = spinel_adapter_row_fill_invoke(v->id_scr, v->id[T_TILE], v->id[T_LUT], f[0], f[1],
                                          f[2], f[3], f[4], f[5], width, id_result);
      break;
    default:
      st = spinel_adapter_col_smear_invoke(v->id_scr, v->id[T_LUT], v->id[T_OFFS], f[0], f[1],
                                           f[2], f[3], f[4], f[5], width, id_result);
      break;
  }
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
  } else if (got != poison) {
    fail("a refused invoke wrote a result");
  }
  return st;
}
#else
#define view_open(v) ((void)(v))
#define view_close(v) ((void)(v))
/* The direct build draws on the caller's own array. */
#define screen_back(v) ((void)(v), 0)

static int32_t call_kernel(const struct job *j, struct view *v) {
  const int64_t *f = j->f;
  int64_t result = 0;
  switch (j->kernel) {
    case K_COL:
      return spinel_core_col_fill(v->scr, v->n_scr, v->pat, v->n[T_PAT], v->lut, v->n[T_LUT],
                                  f[0], f[1], f[2], f[3], f[4], f[5], f[6], width, &result);
    case K_ROW:
      return spinel_core_row_fill(v->scr, v->n_scr, v->tile, v->n[T_TILE], v->lut,
                                  v->n[T_LUT], f[0], f[1], f[2], f[3], f[4], f[5], width,
                                  &result);
    default:
      return spinel_core_col_smear(v->scr, v->n_scr, v->lut, v->n[T_LUT], v->offs,
                                   v->n[T_OFFS], f[0], f[1], f[2], f[3], f[4], f[5], width,
                                   &result);
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

static void parse_job(char **fv, struct job *j) {
  j->kernel = find(kernel_names, N_KERNELS, fv[0]);
  if (j->kernel < 0) fail("a job names no kernel");
  for (int k = 0; k < N_FIELDS; k++) j->f[k] = strcmp(fv[1 + k], "-") == 0 ? 0 : number(fv[1 + k]);
}

static void parse(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) fail("the scene file will not open");
  static char buf[65536];
  while (fgets(buf, sizeof(buf), f)) {
    size_t len = strlen(buf);
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r')) buf[--len] = '\0';
    if (len == 0 || buf[0] == '#') continue;
    char *fv[16];
    int nf = fields(buf, fv, 16);
    int t;
    if (strcmp(fv[0], "size") == 0 && nf == 3) {
      width = number(fv[1]);
      height = number(fv[2]);
      if (width <= 0 || height <= 0 || width * height > MAX_CELLS)
        fail("the screen is out of the harness's range");
    } else if ((t = find(table_names, N_TABLES, fv[0])) >= 0 && nf == 2) {
      for (char *tok = strtok(fv[1], ","); tok; tok = strtok(NULL, ",")) {
        if (n_table[t] == MAX_CELLS - 1) fail("a table is too long");
        table[t][n_table[t]++] = (int32_t)number(tok);
      }
    } else if (strcmp(fv[0], "screen") == 0 && nf == 2) {
      for (char *tok = strtok(fv[1], ","); tok; tok = strtok(NULL, ",")) {
        if (n_expect == MAX_CELLS) fail("the expected screen is too long");
        expect[n_expect++] = (uint8_t)number(tok);
      }
    } else if (strcmp(fv[0], "job") == 0 && nf == 2 + N_FIELDS) {
      if (n_jobs == MAX_JOBS) fail("too many jobs");
      parse_job(fv + 1, &jobs[n_jobs++]);
    } else if (strcmp(fv[0], "check") == 0 && nf == 6 + N_FIELDS) {
      if (n_checks == MAX_JOBS) fail("too many checks");
      struct check *c = &checks[n_checks++];
      snprintf(c->id, sizeof(c->id), "%s", fv[1]);
      parse_job(fv + 2, &c->job);
      char **rest = fv + 3 + N_FIELDS;
      c->shorten = strcmp(rest[0], "-") == 0 ? -1 : find(table_names, N_TABLES, rest[0]);
      if (strcmp(rest[0], "-") != 0 && c->shorten < 0) fail("a check shortens no table");
      c->status = (int32_t)number(rest[1]);
      c->moved = strcmp(rest[2], "-") == 0 ? 0 : (long)number(rest[2]);
    } else {
      fail("a scene line is of no known kind");
    }
  }
  fclose(f);
  if (width == 0) fail("the scene names no size");
  if (n_expect != (size_t)(width * height)) fail("the expected screen is not width x height");
  for (int k = 0; k < N_TABLES; k++)
    if (n_table[k] == 0) fail("the scene leaves a table empty");
}

/* Runs the jobs over a zeroed screen, forwards or backwards. */
static void draw(uint8_t *scr, int backwards) {
  struct view v;
  memset(scr, 0, (size_t)(width * height));
  view_init(&v, scr, -1);
  view_open(&v);
  for (size_t i = 0; i < n_jobs; i++) {
    const struct job *j = &jobs[backwards ? n_jobs - 1 - i : i];
    int32_t st = call_kernel(j, &v);
    if (st != SPINEL_CORE_OK) {
      fprintf(stderr, "harness: job %zu (%s) answered status %d\n", i + 1,
              kernel_names[j->kernel], (int)st);
      exit(1);
    }
  }
  if (screen_back(&v)) fail("an accepted job poisoned the screen");
  view_close(&v);
}

static void scene_guards(void) {
  /* A scene that would pass for the wrong reason is refused. */
  int reached[N_KERNELS] = {0};
  size_t lit = 0;
  for (size_t i = 0; i < n_jobs; i++) reached[jobs[i].kernel] = 1;
  for (int k = 0; k < N_KERNELS; k++)
    if (!reached[k]) fail("the scene never reaches one of the kernels");
  for (size_t i = 0; i < n_expect; i++) lit += expect[i] != 0;
  if (lit == 0) fail("the expected screen is blank, so drawing nothing would match it");
  if (lit == n_expect) fail("the expected screen has no untouched byte to hold the jobs to");
}

static int mode_run(void) {
  static uint8_t scr[MAX_CELLS];
  scene_guards();
  draw(scr, 0);
  for (size_t i = 0; i < n_expect; i++) {
    if (scr[i] != expect[i]) {
      fprintf(stderr, "harness: pixel (%lld, %lld) is %d, the scene says %d\n",
              (long long)(i % (size_t)width), (long long)(i / (size_t)width), (int)scr[i],
              (int)expect[i]);
      return 1;
    }
  }
  printf("run: %zu job(s), %zu byte(s) match\n", n_jobs, n_expect);
  return 0;
}

static int mode_reverse(void) {
  static uint8_t scr[MAX_CELLS];
  scene_guards();
  draw(scr, 1);
  size_t differ = 0;
  for (size_t i = 0; i < n_expect; i++) differ += scr[i] != expect[i];
  if (differ == 0) fail("the jobs run backwards draw the same screen, so their order is not observed");
  printf("reverse: %zu job(s) backwards, %zu byte(s) differ\n", n_jobs, differ);
  return 0;
}

static int mode_refuse(void) {
  static uint8_t scr[MAX_CELLS];
  long refusals = 0, bounds = 0, arithmetic = 0;
  int reached[N_KERNELS] = {0};
  for (size_t i = 0; i < n_checks; i++) {
    const struct check *c = &checks[i];
    struct view v;
    memset(scr, 0, (size_t)(width * height));
    view_init(&v, scr, c->shorten);
    view_open(&v);
    int32_t st = call_kernel(&c->job, &v);
    reached[c->job.kernel] = 1;
    if (st != c->status) {
      fprintf(stderr, "harness: check %s answered status %d, the scene says %d\n", c->id,
              (int)st, (int)c->status);
      return 1;
    }
    if (st == SPINEL_CORE_OK) {
      if (screen_back(&v)) fail("an accepted call poisoned the screen");
    } else {
      refusals++;
      if (st == SPINEL_CORE_BOUNDS) bounds++;
      if (st == SPINEL_CORE_ARITHMETIC) arithmetic++;
#ifdef SPINEL_VIA_ADAPTER
      if (!screen_back(&v)) {
        fprintf(stderr, "harness: check %s: the refusal did not poison the screen\n", c->id);
        return 1;
      }
      if (tables_poisoned(&v)) {
        fprintf(stderr, "harness: check %s: the refusal poisoned a table it only read\n", c->id);
        return 1;
      }
#else
      /* What a direct caller can still read: the pixels drawn before the call
       * stopped, counted from the screen and not from the scene. */
      long changed = 0;
      for (size_t k = 0; k < (size_t)(width * height); k++) changed += scr[k] != 0;
      if (changed != c->moved) {
        fprintf(stderr, "harness: check %s changed %ld cell(s), and declares %ld\n", c->id,
                changed, c->moved);
        return 1;
      }
#endif
    }
    view_close(&v);
  }
  /* The checks have to ask the questions they are there for. */
  if (bounds == 0 || arithmetic == 0) fail("the checks never refuse with both statuses");
  if (refusals == (long)n_checks) fail("no check is accepted, so no edge has its inside");
  for (int k = 0; k < N_KERNELS; k++)
    if (!reached[k]) fail("the checks never reach one of the kernels");
  printf("refuse: %zu check(s), %ld refusal(s)\n", n_checks, refusals);
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 3) fail("usage: harness <scene-file> <run|reverse|refuse>");
  parse(argv[1]);
  if (strcmp(argv[2], "run") == 0) return mode_run();
  if (strcmp(argv[2], "reverse") == 0) return mode_reverse();
  if (strcmp(argv[2], "refuse") == 0) return mode_refuse();
  fail("unknown mode; expected run, reverse or refuse");
  return 2;
}
