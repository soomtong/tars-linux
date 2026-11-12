// KMS master handover probe. "A" plays the terminal, children play the app.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>

struct scr { int fd; uint32_t crtc, conn, fb; struct drm_mode_modeinfo mode; };

static const char *es(int rc) { static char b[64]; if (rc == 0) return "ok"; snprintf(b, sizeof b, "errno %d (%s)", errno, strerror(errno)); return b; }

static int find(struct scr *s) {
    uint32_t crtcs[8], conns[8], encs[8], fbs[8];
    struct drm_mode_card_res r = {0};
    r.crtc_id_ptr = (uintptr_t)crtcs; r.count_crtcs = 8;
    r.connector_id_ptr = (uintptr_t)conns; r.count_connectors = 8;
    r.encoder_id_ptr = (uintptr_t)encs; r.count_encoders = 8;
    r.fb_id_ptr = (uintptr_t)fbs; r.count_fbs = 8;
    if (ioctl(s->fd, DRM_IOCTL_MODE_GETRESOURCES, &r)) return -1;
    printf("    resources: crtcs=%u connectors=%u\n", r.count_crtcs, r.count_connectors);
    if (!r.count_crtcs || !r.count_connectors) return -1;
    s->crtc = crtcs[0]; s->conn = conns[0];
    struct drm_mode_modeinfo modes[32]; uint32_t ce[8];
    struct drm_mode_get_connector c = {0};
    c.connector_id = s->conn;
    ioctl(s->fd, DRM_IOCTL_MODE_GETCONNECTOR, &c);   // first call with no buffers makes the kernel probe modes
    memset(&c, 0, sizeof c); c.connector_id = s->conn; c.modes_ptr = (uintptr_t)modes; c.count_modes = 32;
    c.encoders_ptr = (uintptr_t)ce; c.count_encoders = 8;
    if (ioctl(s->fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) || !c.count_modes) return -1;
    s->mode = modes[0];
    return 0;
}
static int mkfb(struct scr *s) {
    struct drm_mode_create_dumb d = { .width = s->mode.hdisplay, .height = s->mode.vdisplay, .bpp = 32 };
    if (ioctl(s->fd, DRM_IOCTL_MODE_CREATE_DUMB, &d)) return -1;
    struct drm_mode_fb_cmd f = { .width = d.width, .height = d.height, .pitch = d.pitch, .bpp = 32, .depth = 24, .handle = d.handle };
    if (ioctl(s->fd, DRM_IOCTL_MODE_ADDFB, &f)) return -1;
    s->fb = f.fb_id;
    return 0;
}
static int setcrtc(struct scr *s) {
    uint32_t c = s->conn;
    struct drm_mode_crtc m = { .set_connectors_ptr = (uintptr_t)&c, .count_connectors = 1, .crtc_id = s->crtc, .fb_id = s->fb, .mode_valid = 1, .mode = s->mode };
    return ioctl(s->fd, DRM_IOCTL_MODE_SETCRTC, &m);
}
static int dirty(struct scr *s) { struct drm_mode_fb_dirty_cmd d = { .fb_id = s->fb }; return ioctl(s->fd, DRM_IOCTL_MODE_DIRTYFB, &d); }
static void show(struct scr *s, const char *when) {
    struct drm_mode_crtc m = { .crtc_id = s->crtc };
    int rc = ioctl(s->fd, DRM_IOCTL_MODE_GETCRTC, &m);
    printf("    [%s] GETCRTC %s: fb_id=%u mode_valid=%u (A's fb=%u)\n", when, es(rc), m.fb_id, m.mode_valid, s->fb);
}

// The "app": opens card0 itself (like SDL kmsdrm), modesets, tells parent, waits to be told to die.
static pid_t app(int uid, int *to_app, int *from_app) {
    int p1[2], p2[2]; pipe(p1); pipe(p2);
    pid_t pid = fork();
    if (pid) { close(p1[0]); close(p2[1]); *to_app = p1[1]; *from_app = p2[0]; return pid; }
    close(p1[1]); close(p2[0]);
    if (uid) { setgid(uid); setuid(uid); }
    struct scr b = { .fd = open("/dev/dri/card0", O_RDWR) };
    printf("    app(uid %d): open %s\n", getuid(), b.fd < 0 ? es(-1) : "ok");
    if (b.fd >= 0 && find(&b) == 0) {
        printf("    app: mkfb %s\n", es(mkfb(&b)));
        printf("    app: SETCRTC %s (fb=%u)\n", es(setcrtc(&b)), b.fb);
    }
    fflush(stdout);
    write(p2[1], "r", 1);
    char ch; read(p1[0], &ch, 1);   // 'x' = exit cleanly; parent may SIGKILL instead
    _exit(0);
}
static void wait_ready(int fd) { char ch; read(fd, &ch, 1); }

int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    struct scr a = { .fd = open("/dev/dri/card0", O_RDWR) };
    if (a.fd < 0) { printf("open A: %s\n", es(-1)); return 1; }
    chmod("/dev/dri/card0", 0666);
    printf("T0 terminal(A) sets up\n");
    if (find(&a)) { printf("    find failed %s\n", es(-1)); return 1; }
    printf("    A: mkfb %s\n", es(mkfb(&a)));
    printf("    A: SETCRTC %s\n", es(setcrtc(&a)));
    printf("    A: DIRTYFB %s\n", es(dirty(&a)));
    show(&a, "A master");

    int tx, rx; pid_t pid;
    printf("T1 app opens card0 while A is still master\n");
    pid = app(0, &tx, &rx); wait_ready(rx); show(&a, "after app tried");
    write(tx, "x", 1); waitpid(pid, NULL, 0); show(&a, "after that app exited");

    printf("T2 A drops master\n");
    printf("    A: DROP_MASTER %s\n", es(ioctl(a.fd, DRM_IOCTL_DROP_MASTER, 0)));
    printf("    A: DIRTYFB %s\n", es(dirty(&a)));
    printf("    A: SETCRTC %s\n", es(setcrtc(&a)));
    show(&a, "A dropped, nobody master");

    printf("T3 app (root) opens card0 after the drop\n");
    pid = app(0, &tx, &rx); wait_ready(rx); show(&a, "app running");
    printf("    A: SET_MASTER while app holds it: %s\n", es(ioctl(a.fd, DRM_IOCTL_SET_MASTER, 0)));
    printf("    A: DIRTYFB %s\n", es(dirty(&a)));

    printf("T4 app is SIGKILLed\n");
    kill(pid, SIGKILL); waitpid(pid, NULL, 0); show(&a, "app dead, before reclaim");
    printf("    A: DIRTYFB before SET_MASTER %s\n", es(dirty(&a)));
    printf("    A: SET_MASTER %s\n", es(ioctl(a.fd, DRM_IOCTL_SET_MASTER, 0)));
    show(&a, "A master again, before modeset");
    printf("    A: DIRTYFB before modeset %s\n", es(dirty(&a)));
    printf("    A: SETCRTC %s\n", es(setcrtc(&a)));
    printf("    A: DIRTYFB %s\n", es(dirty(&a)));
    show(&a, "A restored");

    printf("T5 non-root app (uid 1000) after a drop\n");
    printf("    A: DROP_MASTER %s\n", es(ioctl(a.fd, DRM_IOCTL_DROP_MASTER, 0)));
    pid = app(1000, &tx, &rx); wait_ready(rx); show(&a, "uid-1000 app running");
    write(tx, "x", 1); waitpid(pid, NULL, 0); show(&a, "uid-1000 app exited cleanly");
    printf("    A: SET_MASTER %s\n", es(ioctl(a.fd, DRM_IOCTL_SET_MASTER, 0)));
    printf("    A: SETCRTC %s\n", es(setcrtc(&a)));

    printf("T6 lease\n");
    uint32_t objs[2] = { a.crtc, a.conn };
    struct drm_mode_create_lease cl = { .object_ids = (uintptr_t)objs, .object_count = 2, .flags = O_CLOEXEC };
    int rc = ioctl(a.fd, DRM_IOCTL_MODE_CREATE_LEASE, &cl);
    printf("    A: CREATE_LEASE %s (lessee_id=%u fd=%d)\n", es(rc), cl.lessee_id, cl.fd);
    if (rc == 0) {
        struct scr l = { .fd = cl.fd };
        if (find(&l) == 0) {
            printf("    lessee: mkfb %s\n", es(mkfb(&l)));
            printf("    lessee: SETCRTC %s (fb=%u)\n", es(setcrtc(&l)), l.fb);
        }
        show(&a, "leased, lessee scanning out");
        printf("    A: DIRTYFB while leased %s\n", es(dirty(&a)));
        printf("    A: SETCRTC while leased %s\n", es(setcrtc(&a)));
        show(&a, "after A's SETCRTC while leased");
        printf("    lessee: SETCRTC again %s\n", es(setcrtc(&l)));
        struct drm_mode_revoke_lease rv = { .lessee_id = cl.lessee_id };
        printf("    A: REVOKE_LEASE %s\n", es(ioctl(a.fd, DRM_IOCTL_MODE_REVOKE_LEASE, &rv)));
        show(&a, "revoked, before A redraws");
        printf("    lessee: SETCRTC after revoke %s\n", es(setcrtc(&l)));
        printf("    lessee: find after revoke %s\n", es(find(&l)));
        printf("    A: SETCRTC %s\n", es(setcrtc(&a)));
        close(l.fd); show(&a, "lessee fd closed");
    }
    printf("PROBE DONE\n");
    return 0;
}
