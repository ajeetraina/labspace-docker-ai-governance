package main

import (
	"bufio"
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/client"
	"github.com/gorilla/websocket"
	"github.com/hpcloud/tail"
)

//go:embed static
var staticFS embed.FS

// Event is the normalised shape we send to the frontend.
// MCPServer is set when Resource looks like a known MCP server endpoint
// (mcp.notion.com, mcp.linear.app, registry.modelcontextprotocol.io, …).
type Event struct {
	Source    string                 `json:"source"`
	Time      string                 `json:"time"`
	Kind      string                 `json:"kind"`
	Decision  string                 `json:"decision,omitempty"`
	Resource  string                 `json:"resource,omitempty"`
	Rule      string                 `json:"rule,omitempty"`
	Reason    string                 `json:"reason,omitempty"`
	Origin    string                 `json:"origin,omitempty"`
	User      string                 `json:"user,omitempty"`
	Sandbox   string                 `json:"sandbox,omitempty"`
	Agent     string                 `json:"agent,omitempty"`
	MCPServer bool                   `json:"mcp_server,omitempty"`
	Raw       map[string]interface{} `json:"raw"`
}

type hub struct {
	mu      sync.Mutex
	clients map[*websocket.Conn]bool
	history []Event
	maxHist int
}

func newHub() *hub {
	return &hub{clients: make(map[*websocket.Conn]bool), maxHist: 1000}
}

func (h *hub) add(client *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.clients[client] = true
	for _, e := range h.history {
		_ = client.WriteJSON(e)
	}
}

func (h *hub) remove(client *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.clients, client)
	_ = client.Close()
}

func (h *hub) broadcast(e Event) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.history = append(h.history, e)
	if len(h.history) > h.maxHist {
		h.history = h.history[len(h.history)-h.maxHist:]
	}
	for c := range h.clients {
		if err := c.WriteJSON(e); err != nil {
			delete(h.clients, c)
			_ = c.Close()
		}
	}
}

func (h *hub) snapshot() []Event {
	h.mu.Lock()
	defer h.mu.Unlock()
	out := make([]Event, len(h.history))
	copy(out, h.history)
	return out
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

// Synthesised user identity. v0.32.0 does not emit this natively in the
// daemon log, so we stamp every event with whoever started the dashboard.
var labspaceUser string

// MCP server destinations we know about. Resources matching any of these
// patterns get MCPServer=true so the frontend can group them.
var mcpServerPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)\bmcp\.[a-z0-9.-]+`),
	regexp.MustCompile(`(?i)registry\.modelcontextprotocol\.io`),
	regexp.MustCompile(`(?i)\bmcp-[a-z0-9.-]+`),
}

func isMCPDestination(s string) bool {
	if s == "" {
		return false
	}
	for _, re := range mcpServerPatterns {
		if re.MatchString(s) {
			return true
		}
	}
	return false
}

// ---------- sbx daemon.log ----------

func tailSbxLog(ctx context.Context, path string, h *hub) {
	t, err := tail.TailFile(path, tail.Config{
		Follow:    true,
		ReOpen:    true,
		MustExist: false,
		Logger:    tail.DiscardingLogger,
	})
	if err != nil {
		log.Printf("sbx tail: %v", err)
		return
	}
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case line, ok := <-t.Lines:
			if !ok {
				return
			}
			parseAndBroadcastSbx(line.Text, h)
		}
	}
}

func parseAndBroadcastSbx(line string, h *hub) {
	var raw map[string]interface{}
	if err := json.Unmarshal([]byte(line), &raw); err != nil {
		return
	}
	msg, _ := raw["msg"].(string)
	if msg != "governance policy evaluation" {
		return
	}
	allowed, _ := raw["allowed"].(bool)
	decision := "allow"
	if !allowed {
		decision = "deny"
	}
	rule, _ := raw["policy_matched_rule"].(string)
	if rule == "" {
		rule = "(default-deny)"
	}
	reason, _ := raw["policy_deny_reason"].(string)
	origin, _ := raw["policy_source"].(string)
	resource, _ := raw["resource_value"].(string)
	t, _ := raw["time"].(string)
	sandbox, _ := raw["sandbox"].(string)
	if sandbox == "" {
		// some events use 'session' as the sandbox name
		sandbox, _ = raw["session"].(string)
	}
	agent, _ := raw["agent"].(string)

	e := Event{
		Source:    "sbx",
		Time:      t,
		Kind:      "policy",
		Decision:  decision,
		Resource:  resource,
		Rule:      rule,
		Reason:    reason,
		Origin:    origin,
		User:      labspaceUser,
		Sandbox:   sandbox,
		Agent:     agent,
		MCPServer: isMCPDestination(resource),
		Raw:       raw,
	}
	h.broadcast(e)
}

// ---------- sbx mcp.log (logfmt, not JSON) ----------

var logfmtKV = regexp.MustCompile(`(\w+)=(?:"([^"]*)"|(\[[^\]]*\])|(\S+))`)

func tailMcpLog(ctx context.Context, path string, h *hub) {
	t, err := tail.TailFile(path, tail.Config{
		Follow:    true,
		ReOpen:    true,
		MustExist: false,
		Logger:    tail.DiscardingLogger,
	})
	if err != nil {
		log.Printf("mcp.log tail: %v", err)
		return
	}
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case line, ok := <-t.Lines:
			if !ok {
				return
			}
			parseMcpLog(line.Text, h)
		}
	}
}

func parseMcpLog(line string, h *hub) {
	if line == "" {
		return
	}
	fields := map[string]string{}
	for _, m := range logfmtKV.FindAllStringSubmatch(line, -1) {
		k := m[1]
		v := m[2]
		if v == "" {
			v = m[3]
		}
		if v == "" {
			v = m[4]
		}
		fields[k] = v
	}
	msg := fields["msg"]
	if msg == "" {
		return
	}
	t := fields["time"]
	if t == "" {
		t = time.Now().UTC().Format(time.RFC3339Nano)
	}
	level := strings.ToLower(fields["level"])
	decision := "info"
	if level == "error" {
		decision = "deny"
	}
	sandbox := fields["name"]
	if sandbox == "" {
		sandbox = fields["session"]
	}
	raw := map[string]interface{}{}
	for k, v := range fields {
		raw[k] = v
	}
	e := Event{
		Source:   "mcp-lifecycle",
		Time:     t,
		Kind:     "mcp-lifecycle",
		Decision: decision,
		Resource: firstNonEmpty(fields["url"], fields["servers"], fields["inline_servers"], fields["workspace"]),
		Rule:     msg,
		Reason:   firstNonEmpty(fields["err"], fields["error"]),
		User:     labspaceUser,
		Sandbox:  sandbox,
		Raw:      raw,
	}
	h.broadcast(e)
}

func firstNonEmpty(vs ...string) string {
	for _, v := range vs {
		if v != "" {
			return v
		}
	}
	return ""
}

// ---------- docker/mcp-gateway container logs ----------

func tailMcpGateway(ctx context.Context, h *hub) {
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		log.Printf("docker client: %v", err)
		return
	}
	defer cli.Close()

	seen := make(map[string]context.CancelFunc)
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	check := func() {
		containers, err := cli.ContainerList(ctx, container.ListOptions{All: false})
		if err != nil {
			log.Printf("container list: %v", err)
			return
		}
		alive := make(map[string]bool)
		for _, c := range containers {
			if !strings.Contains(c.Image, "mcp-gateway") {
				continue
			}
			alive[c.ID] = true
			if _, ok := seen[c.ID]; ok {
				continue
			}
			cctx, cancel := context.WithCancel(ctx)
			seen[c.ID] = cancel
			go streamContainerLogs(cctx, cli, c.ID, h)
		}
		for id, cancel := range seen {
			if !alive[id] {
				cancel()
				delete(seen, id)
			}
		}
	}

	check()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			check()
		}
	}
}

func streamContainerLogs(ctx context.Context, cli *client.Client, id string, h *hub) {
	rc, err := cli.ContainerLogs(ctx, id, container.LogsOptions{
		ShowStdout: true,
		ShowStderr: true,
		Follow:     true,
		Tail:       "0",
		Timestamps: true,
	})
	if err != nil {
		log.Printf("container logs %s: %v", id[:12], err)
		return
	}
	defer rc.Close()
	scanner := bufio.NewScanner(stripDockerLogHeader(rc))
	scanner.Buffer(make([]byte, 64*1024), 1024*1024)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.TrimSpace(line) == "" {
			continue
		}
		ts := time.Now().UTC().Format(time.RFC3339Nano)
		parts := strings.SplitN(line, " ", 2)
		body := line
		if len(parts) == 2 {
			if t, err := time.Parse(time.RFC3339Nano, parts[0]); err == nil {
				ts = t.Format(time.RFC3339Nano)
				body = parts[1]
			}
		}
		decision := "info"
		lower := strings.ToLower(body)
		if strings.Contains(lower, "denied") || strings.Contains(lower, "forbidden") || strings.Contains(lower, "error") {
			decision = "deny"
		}
		e := Event{
			Source:   "mcp-gateway",
			Time:     ts,
			Kind:     "mcp",
			Decision: decision,
			Resource: extractMcpResource(body),
			Rule:     extractMcpRule(body),
			User:     labspaceUser,
			Raw:      map[string]interface{}{"line": body, "container": id[:12]},
		}
		h.broadcast(e)
	}
}

// Docker engine multiplexes stdout/stderr with an 8-byte header per chunk.
// Strip it so log lines parse cleanly.
type dockerLogReader struct{ r io.Reader }

func (d *dockerLogReader) Read(p []byte) (int, error) {
	hdr := make([]byte, 8)
	if _, err := io.ReadFull(d.r, hdr); err != nil {
		return 0, err
	}
	size := int(hdr[4])<<24 | int(hdr[5])<<16 | int(hdr[6])<<8 | int(hdr[7])
	if size <= 0 {
		return 0, nil
	}
	if size > len(p) {
		size = len(p)
	}
	return io.ReadFull(d.r, p[:size])
}

func stripDockerLogHeader(r io.Reader) io.Reader { return &dockerLogReader{r: r} }

// Heuristics for extracting tool / resource info from gateway --verbose=true
// stdout. Best-effort — not a structured audit.
var (
	reToolName  = regexp.MustCompile(`(?i)tool[ =:]+"?([a-z0-9_./-]+)"?`)
	reServerArg = regexp.MustCompile(`(?i)server[ =:]+"?([a-z0-9_./-]+)"?`)
)

func extractMcpResource(line string) string {
	if m := reServerArg.FindStringSubmatch(line); len(m) > 1 {
		return "server=" + m[1]
	}
	if m := reToolName.FindStringSubmatch(line); len(m) > 1 {
		return "tool=" + m[1]
	}
	return ""
}

func extractMcpRule(line string) string {
	switch {
	case strings.Contains(line, "CallToolRequest"):
		return "call-tool"
	case strings.Contains(line, "ListToolsRequest"):
		return "list-tools"
	case strings.Contains(line, "ListResourcesRequest"):
		return "list-resources"
	case strings.Contains(line, "ListPromptsRequest"):
		return "list-prompts"
	case strings.Contains(line, "ListResourceTemplatesRequest"):
		return "list-resource-templates"
	default:
		return ""
	}
}

// ---------- main ----------

func main() {
	sbxLog := os.Getenv("SBX_DAEMON_LOG")
	if sbxLog == "" {
		sbxLog = "/var/log/sbx/sandboxes/sandboxd/daemon.log"
	}
	mcpLog := os.Getenv("SBX_MCP_LOG")
	if mcpLog == "" {
		// Derive from sbxLog by replacing the leaf
		mcpLog = strings.TrimSuffix(sbxLog, "/daemon.log") + "/mcp/mcp.log"
	}
	addr := os.Getenv("LISTEN_ADDR")
	if addr == "" {
		addr = ":8090"
	}
	labspaceUser = firstNonEmpty(
		os.Getenv("LABSPACE_USER"),
		os.Getenv("USER"),
		"unknown",
	)

	h := newHub()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go tailSbxLog(ctx, sbxLog, h)
	go tailMcpLog(ctx, mcpLog, h)
	go tailMcpGateway(ctx, h)

	mux := http.NewServeMux()

	mux.HandleFunc("/api/events", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(h.snapshot())
	})

	mux.HandleFunc("/api/meta", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"user":             labspaceUser,
			"sbx_daemon_log":   sbxLog,
			"sbx_mcp_log":      mcpLog,
			"user_is_synth":    true,
			"native_user_in_v0_32_0": false,
		})
	})

	mux.HandleFunc("/api/ws", func(w http.ResponseWriter, r *http.Request) {
		c, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		h.add(c)
		defer h.remove(c)
		for {
			if _, _, err := c.NextReader(); err != nil {
				return
			}
		}
	})

	mux.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})

	sub, _ := fs.Sub(staticFS, "static")
	mux.Handle("/", http.FileServer(http.FS(sub)))

	log.Printf("observability listening on %s (sbx=%s, mcp=%s, user=%s)", addr, sbxLog, mcpLog, labspaceUser)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}
