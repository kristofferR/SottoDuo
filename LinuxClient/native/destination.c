/* One take, one accessible, one mutation. No key injection or clipboard access. */
#include <atspi/atspi.h>
#include <json-glib/json-glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <signal.h>
#include <unistd.h>

static AtspiAccessible *target;
static gchar *original;
static gint caret;
static gboolean invalidated;
static gint64 deadline;
static guint visited;

static void reply(const char *status) { puts(status); fflush(stdout); }

static gboolean ordinary_ancestors(AtspiAccessible *obj) {
  AtspiAccessible *current = g_object_ref(obj);
  for (guint depth = 0; current && depth < 32; depth++) {
    atspi_accessible_clear_cache_single(current);
    GError *error = NULL;
    AtspiRole role = atspi_accessible_get_role(current, &error);
    if (error || role == ATSPI_ROLE_PASSWORD_TEXT || role == ATSPI_ROLE_TERMINAL) {
      g_clear_error(&error); g_object_unref(current); return FALSE;
    }
    if (role == ATSPI_ROLE_APPLICATION) { g_object_unref(current); return TRUE; }
    AtspiAccessible *parent = atspi_accessible_get_parent(current, &error);
    g_object_unref(current);
    if (error) { g_clear_error(&error); g_clear_object(&parent); return FALSE; }
    current = parent;
  }
  g_clear_object(&current);
  return FALSE;
}

static gboolean safe(AtspiAccessible *obj) {
  atspi_accessible_clear_cache(obj);
  GError *error = NULL;
  AtspiRole role = atspi_accessible_get_role(obj, &error);
  if (error) { g_error_free(error); return FALSE; }
  /* Terminals, password fields and unknown roles cannot prove a safe text destination. */
  if (role != ATSPI_ROLE_ENTRY && role != ATSPI_ROLE_TEXT) return FALSE;
  AtspiStateSet *states = atspi_accessible_get_state_set(obj);
  if (!states) return FALSE;
  gboolean valid = atspi_state_set_contains(states, ATSPI_STATE_FOCUSED) &&
    atspi_state_set_contains(states, ATSPI_STATE_EDITABLE) &&
    atspi_state_set_contains(states, ATSPI_STATE_ENABLED) &&
    atspi_state_set_contains(states, ATSPI_STATE_SHOWING) &&
    !atspi_state_set_contains(states, ATSPI_STATE_DEFUNCT);
  g_object_unref(states);
  return valid;
}

static AtspiAccessible *find(AtspiAccessible *obj, guint depth) {
  if (++visited > 512 || depth > 32 || g_get_monotonic_time() > deadline) return NULL;
  if (safe(obj)) return g_object_ref(obj);
  GError *error = NULL;
  gint count = atspi_accessible_get_child_count(obj, &error);
  if (error) { g_error_free(error); return NULL; }
  for (gint i = 0; i < count && visited <= 512 && g_get_monotonic_time() <= deadline; i++) {
    AtspiAccessible *child = atspi_accessible_get_child_at_index(obj, i, &error);
    if (error) { g_clear_error(&error); continue; }
    if (!child) continue;
    AtspiAccessible *found = find(child, depth + 1);
    g_object_unref(child);
    if (found) return found;
  }
  return NULL;
}

static gchar *snapshot(gint *position) {
  if (!safe(target) || !ordinary_ancestors(target)) return NULL;
  AtspiText *text = atspi_accessible_get_text_iface(target);
  AtspiEditableText *editable = atspi_accessible_get_editable_text_iface(target);
  if (!text || !editable) { g_clear_object(&text); g_clear_object(&editable); return NULL; }
  g_object_unref(editable);
  GError *error = NULL;
  gint count = atspi_text_get_character_count(text, &error);
  gint selection_count = error ? -1 : atspi_text_get_n_selections(text, &error);
  *position = error ? -1 : atspi_text_get_caret_offset(text, &error);
  gchar *value = NULL;
  if (!error && count >= 0 && count <= 65536 && selection_count == 0 && *position >= 0 && *position <= count)
    value = atspi_text_get_text(text, 0, count, &error);
  if (error) { g_clear_pointer(&value, g_free); g_error_free(error); }
  g_object_unref(text);
  if (!value) return NULL;
  gchar *hash = g_compute_checksum_for_string(G_CHECKSUM_SHA256, value, -1);
  g_free(value);
  return hash;
}

static void changed(AtspiEvent *event, void *unused) {
  (void)unused;
  if (target && (event->source == target ||
      (g_str_has_prefix(event->type, "object:state-changed:focused") && event->detail1)))
    invalidated = TRUE;
  g_boxed_free(ATSPI_TYPE_EVENT, event);
}

static gboolean input(GIOChannel *channel, GIOCondition condition, gpointer unused) {
  (void)unused;
  if (!(condition & G_IO_IN)) { atspi_event_quit(); return G_SOURCE_REMOVE; }
  gchar *line = NULL;
  gsize length = 0;
  GIOStatus status = g_io_channel_read_line(channel, &line, &length, NULL, NULL);
  if (status == G_IO_STATUS_AGAIN) return G_SOURCE_CONTINUE;
  if (status != G_IO_STATUS_NORMAL || length > 262144) goto preview;
  JsonParser *parser = json_parser_new();
  gboolean parsed = json_parser_load_from_data(parser, line, length, NULL);
  JsonNode *node = parsed ? json_parser_get_root(parser) : NULL;
  const gchar *value = node && JSON_NODE_HOLDS_VALUE(node) && json_node_get_value_type(node) == G_TYPE_STRING ? json_node_get_string(node) : NULL;
  gint position = -1;
  gchar *current = invalidated ? NULL : snapshot(&position);
  gboolean valid = current && g_strcmp0(original, current) == 0 && position == caret && value &&
    strlen(value) <= 131072 && g_utf8_validate(value, -1, NULL) && !strchr(value, '\r');
  g_free(current);
  if (valid) {
    AtspiEditableText *editable = atspi_accessible_get_editable_text_iface(target);
    if (editable) {
      GError *error = NULL;
      gboolean inserted = atspi_editable_text_insert_text(editable, caret, value, (gint)strlen(value), &error);
      /* Even a false reply may follow partial application. Never retry. */
      reply(inserted && !error ? "inserted" : "uncertain");
      g_clear_error(&error);
      g_object_unref(editable);
    } else reply("preview");
  } else reply("preview");
  g_object_unref(parser);
  g_free(line);
  atspi_event_quit();
  return G_SOURCE_REMOVE;
preview:
  reply("preview");
  g_free(line);
  atspi_event_quit();
  return G_SOURCE_REMOVE;
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  char *end = NULL;
  guint64 pid = g_ascii_strtoull(argv[1], &end, 10);
  if (!pid || pid > G_MAXUINT || *end) return 2;
  pid_t parent = getppid();
  if (prctl(PR_SET_PDEATHSIG, SIGKILL) || getppid() != parent) return 2;
  /* Allow 174 s capture, drain, 120 s processing and bounded delivery RPCs. */
  alarm(330);
  if (atspi_init()) { reply("preview"); return 0; }
  atspi_set_timeout(100, 100);
  deadline = g_get_monotonic_time() + 1000000;
  AtspiEventListener *listener = atspi_event_listener_new(changed, NULL, NULL);
  const char *events[] = { "object:state-changed:focused", "object:text-changed", "object:text-caret-moved", "object:text-selection-changed", "object:state-changed:defunct" };
  for (guint i = 0; i < G_N_ELEMENTS(events); i++) {
    if (!atspi_event_listener_register(listener, events[i], NULL)) { reply("preview"); return 0; }
  }
  AtspiAccessible *desktop = atspi_get_desktop(0);
  gint count = desktop ? atspi_accessible_get_child_count(desktop, NULL) : 0;
  for (gint i = 0; i < count && !target && g_get_monotonic_time() <= deadline; i++) {
    AtspiAccessible *app = atspi_accessible_get_child_at_index(desktop, i, NULL);
    if (!app) continue;
    if (atspi_accessible_get_process_id(app, NULL) == pid) target = find(app, 0);
    g_object_unref(app);
  }
  g_clear_object(&desktop);
  if (!target || !(original = snapshot(&caret))) { reply("preview"); atspi_exit(); return 0; }
  reply("ready");
  GIOChannel *channel = g_io_channel_unix_new(STDIN_FILENO);
  g_io_channel_set_flags(channel, G_IO_FLAG_NONBLOCK, NULL);
  g_io_add_watch(channel, G_IO_IN | G_IO_HUP | G_IO_ERR, input, NULL);
  atspi_event_main();
  g_io_channel_unref(channel);
  g_free(original);
  g_object_unref(target);
  g_object_unref(listener);
  atspi_exit();
  return 0;
}
