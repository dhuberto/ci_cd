// =============================================================================
// main.go — TodoList (Go + PostgreSQL)
// =============================================================================
// Aplicação web minimalista que cadastra nomes em um banco Postgres.
// Mesma stack do repositório dhuberto/docker.
//
// Stack:
//   - net/http (stdlib)  → servidor HTTP
//   - html/template      → renderização HTML com auto-escape
//   - database/sql       → camada de banco
//   - github.com/lib/pq  → driver Postgres (única dependência)
//
// Variáveis de ambiente:
//   DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME → conexão Postgres
//   APP_NAME   → título exibido na interface (default: "TodoList")
//   APP_PORT   → porta HTTP (default: 5000)
//   APP_COLOR  → cor do tema (purple/blue/green/...)
//   IMAGE_TAGS → tags da imagem, injetadas pelo CI no build
//
// Rotas:
//   GET  /              → lista nomes + formulário
//   POST /cadastrar     → insere um nome
//   GET  /excluir/{id}  → remove um nome
//   GET  /healthz       → health check (usado pelo Kubernetes)
// =============================================================================

package main

import (
	"database/sql"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

// -----------------------------------------------------------------------------
// Tipos e estado global
// -----------------------------------------------------------------------------

type Nome struct {
	ID   int
	Nome string
}

type pageData struct {
	AppName    string
	Color      string
	StatusCls  string
	StatusText string
	Nomes      []Nome
	ImageTags  []string
	Error      string
}

var (
	db       *sql.DB
	tmpl     *template.Template
	appName  string
	appColor string
	tags     []string
)

// -----------------------------------------------------------------------------
// Template HTML
// -----------------------------------------------------------------------------
// Layout minimalista, com a cor vinda de APP_COLOR (essencial para o
// Blue/Green: cada slot pinta a interface de uma cor).

const pageTemplate = `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>{{ .AppName }}</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 600px; margin: 40px auto; padding: 20px; background: #f5f5f5; }
    .card { background: white; border-radius: 16px; padding: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
    h1 { color: {{ .Color }}; }
    .status { display: inline-block; padding: 6px 12px; border-radius: 20px; font-size: 14px; font-weight: bold; margin-bottom: 20px; }
    .online { background: #c6f7d0; color: #0e5e2e; }
    .offline { background: #fed7d7; color: #9b2c2c; }
    input[type="text"] { width: 100%; padding: 10px; margin: 8px 0; border-radius: 8px; border: 1px solid #ccc; box-sizing: border-box; }
    button { background: {{ .Color }}; color: white; border: none; padding: 10px 16px; border-radius: 8px; cursor: pointer; }
    ul { list-style: none; padding: 0; }
    li { background: #f0f2f5; margin: 8px 0; padding: 10px; border-radius: 8px; display: flex; align-items: center; justify-content: space-between; }
    .delete-btn { background: #e53e3e; color: white; text-decoration: none; padding: 5px 10px; border-radius: 6px; font-size: 12px; }
    .error { background: #fed7d7; color: #9b2c2c; padding: 10px; border-radius: 8px; margin-top: 16px; }
    footer { text-align: center; margin-top: 24px; font-size: 12px; color: #777; }
  </style>
</head>
<body>
  <div class="card">
    <h1>📝 {{ .AppName }}</h1>
    <div class="status {{ .StatusCls }}">💾 Banco {{ .StatusText }}</div>
    <form action="/cadastrar" method="post">
      <input type="text" name="nome" placeholder="Digite um nome" required maxlength="255" autocomplete="off">
      <button type="submit">Cadastrar</button>
    </form>
    <h2>📋 Últimos nomes</h2>
    {{ if .Error }}<div class="error">⚠️ {{ .Error }}</div>{{ end }}
    {{ if .Nomes }}
      <ul>
      {{ range .Nomes }}
        <li>
          <span>{{ .Nome }}</span>
          <a href="/excluir/{{ .ID }}" class="delete-btn" onclick="return confirm('Remover {{ .Nome }}?')">🗑️ Excluir</a>
        </li>
      {{ end }}
      </ul>
    {{ else }}
      <p>Nenhum nome cadastrado ainda.</p>
    {{ end }}
    <footer>Go + PostgreSQL + Docker</footer>
  </div>
</body>
</html>`

// -----------------------------------------------------------------------------
// Configuração
// -----------------------------------------------------------------------------

// env lê variável de ambiente ou retorna default.
func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// parseTags transforma "user/app:a,user/app:b" em ["a", "b"].
func parseTags(raw string) []string {
	raw = strings.ReplaceAll(raw, ",", "\n")
	var out []string
	for _, line := range strings.Split(raw, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if i := strings.LastIndex(line, ":"); i >= 0 {
			out = append(out, line[i+1:])
		} else {
			out = append(out, line)
		}
	}
	return out
}

// -----------------------------------------------------------------------------
// Banco
// -----------------------------------------------------------------------------

func openDB() (*sql.DB, error) {
	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable connect_timeout=5",
		env("DB_HOST", "postgres"),
		env("DB_PORT", "5432"),
		env("DB_USER", "postgres"),
		env("DB_PASSWORD", "postgres"),
		env("DB_NAME", "postgres"),
	)
	return sql.Open("postgres", dsn)
}

func initDB() error {
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS nomes (
			id         SERIAL PRIMARY KEY,
			nome       VARCHAR(255) NOT NULL,
			created_at TIMESTAMP DEFAULT NOW()
		)`)
	return err
}

func waitForDB() {
	for i := 1; i <= 30; i++ {
		if err := db.Ping(); err == nil {
			if err := initDB(); err == nil {
				log.Println("✅ Conectado ao PostgreSQL")
				log.Println("✅ Tabelas sincronizadas")
				return
			}
		}
		log.Printf("Aguardando banco... tentativa %d/30", i)
		time.Sleep(5 * time.Second)
	}
	log.Fatal("Banco não ficou pronto a tempo")
}

// -----------------------------------------------------------------------------
// Handlers
// -----------------------------------------------------------------------------

func index(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	data := pageData{
		AppName:    appName,
		Color:      appColor,
		StatusCls:  "online",
		StatusText: "ONLINE",
		ImageTags:  tags,
	}

	rows, err := db.Query("SELECT id, nome FROM nomes ORDER BY created_at DESC")
	if err != nil {
		log.Printf("Erro ao listar: %v", err)
		data.StatusCls = "offline"
		data.StatusText = "OFFLINE"
		data.Error = "Banco de dados indisponível."
	} else {
		defer rows.Close()
		for rows.Next() {
			var n Nome
			if err := rows.Scan(&n.ID, &n.Nome); err == nil {
				data.Nomes = append(data.Nomes, n)
			}
		}
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := tmpl.Execute(w, data); err != nil {
		log.Printf("Erro ao renderizar: %v", err)
	}
}

func cadastrar(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Método não permitido", http.StatusMethodNotAllowed)
		return
	}
	if err := r.ParseForm(); err != nil {
		http.Error(w, "Formulário inválido", http.StatusBadRequest)
		return
	}
	nome := strings.TrimSpace(r.FormValue("nome"))
	if nome != "" {
		if _, err := db.Exec("INSERT INTO nomes (nome) VALUES ($1)", nome); err != nil {
			log.Printf("Erro ao inserir: %v", err)
			http.Error(w, "Erro ao cadastrar", http.StatusInternalServerError)
			return
		}
	}
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func excluir(w http.ResponseWriter, r *http.Request) {
	idStr := strings.TrimPrefix(r.URL.Path, "/excluir/")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		http.Error(w, "ID inválido", http.StatusBadRequest)
		return
	}
	if _, err := db.Exec("DELETE FROM nomes WHERE id = $1", id); err != nil {
		log.Printf("Erro ao excluir: %v", err)
		http.Error(w, "Erro ao excluir", http.StatusInternalServerError)
		return
	}
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func healthz(w http.ResponseWriter, r *http.Request) {
	if err := db.Ping(); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = w.Write([]byte("db offline"))
		return
	}
	_, _ = w.Write([]byte("ok"))
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------

func main() {
	appName = env("APP_NAME", "TodoList")
	appColor = env("APP_COLOR", "#64748b")
	port := env("APP_PORT", "5000")
	tags = parseTags(env("IMAGE_TAGS", ""))

	var err error
	tmpl, err = template.New("page").Parse(pageTemplate)
	if err != nil {
		log.Fatalf("Erro no template: %v", err)
	}

	db, err = openDB()
	if err != nil {
		log.Fatalf("Erro ao abrir DB: %v", err)
	}
	defer db.Close()

	waitForDB()

	mux := http.NewServeMux()
	mux.HandleFunc("/", index)
	mux.HandleFunc("/cadastrar", cadastrar)
	mux.HandleFunc("/excluir/", excluir)
	mux.HandleFunc("/healthz", healthz)

	log.Printf("🚀 Servidor em http://0.0.0.0:%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatal(err)
	}
}
