/* SPDX-License-Identifier: LGPL-2.1 */
/*
 * Copyright (C) 2019, VMware, Tzvetomir Stoyanov <tz.stoyanov@gmail.com>
 *
 */
#ifndef _TRACE_FS_LOCAL_H
#define _TRACE_FS_LOCAL_H

#define __hidden __attribute__((visibility ("hidden")))
#define __weak __attribute__((weak))

#define ARRAY_SIZE(array) (sizeof(array) / sizeof((array)[0]))

/* Will cause a division by zero warning if cond is true */
#define BUILD_BUG_ON(cond)			\
	do { if (!(1/!(cond))) { } } while (0)

struct tracefs_options_mask {
	unsigned long long	mask;
};

struct tracefs_instance {
	struct tracefs_options_mask	supported_opts;
	struct tracefs_options_mask	enabled_opts;
	char				*trace_dir;
	char				*name;
	pthread_mutex_t			lock;
	int				flags;
	int				ftrace_filter_fd;
	int				ftrace_notrace_fd;
	int				ftrace_marker_fd;
	int				ftrace_marker_raw_fd;
};

extern pthread_mutex_t toplevel_lock;

static inline pthread_mutex_t *trace_get_lock(struct tracefs_instance *instance)
{
	return instance ? &instance->lock : &toplevel_lock;
}

/* Can be overridden */
void tracefs_warning(const char *fmt, ...);

int str_read_file(const char *file, char **buffer, bool warn);
char *trace_append_file(const char *dir, const char *name);
char *trace_find_tracing_dir(void);

#ifndef ACCESSPERMS
#define ACCESSPERMS (S_IRWXU|S_IRWXG|S_IRWXO) /* 0777 */
#endif

#ifndef ALLPERMS
#define ALLPERMS (S_ISUID|S_ISGID|S_ISVTX|S_IRWXU|S_IRWXG|S_IRWXO) /* 07777 */
#endif

#ifndef DEFFILEMODE
#define DEFFILEMODE (S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP|S_IROTH|S_IWOTH) /* 0666*/
#endif

struct tracefs_options_mask *
supported_opts_mask(struct tracefs_instance *instance);

struct tracefs_options_mask *
enabled_opts_mask(struct tracefs_instance *instance);

#endif /* _TRACE_FS_LOCAL_H */
