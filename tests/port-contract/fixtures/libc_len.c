/* a second member of the C library, so that an object's definition of c_len
 * can shadow it as a port's getenv shadows the library's */
int c_len(const char *s)
{
	int n = 0;

	while (s[n])
		n++;
	return n;
}
