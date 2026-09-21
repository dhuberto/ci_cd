// =============================================================================
// main_test.go — testes unitários
// =============================================================================
package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestExcluirIDInvalido(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/excluir/abc", nil)
	rec := httptest.NewRecorder()
	excluir(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("esperado 400, recebeu %d", rec.Code)
	}
}

func TestCadastrarMetodoErrado(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/cadastrar", nil)
	rec := httptest.NewRecorder()
	cadastrar(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("esperado 405, recebeu %d", rec.Code)
	}
}

func TestIndexRotaInexistente(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/qualquer", nil)
	rec := httptest.NewRecorder()
	index(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Errorf("esperado 404, recebeu %d", rec.Code)
	}
}

func TestParseTags(t *testing.T) {
	if got := parseTags(""); len(got) != 0 {
		t.Errorf("esperado vazio, recebeu %v", got)
	}
	if got := parseTags("user/app:latest"); len(got) != 1 || got[0] != "latest" {
		t.Errorf("esperado [latest], recebeu %v", got)
	}
	if got := parseTags("user/app:PR-2, user/app:abc123");
		len(got) != 2 || got[0] != "PR-2" || got[1] != "abc123" {
		t.Errorf("esperado [PR-2 abc123], recebeu %v", got)
	}
}

func TestTemplateCompila(t *testing.T) {
	if _, err := parseTemplateForTest(); err != nil {
		t.Errorf("template não compila: %v", err)
	}
}

var _ = strings.TrimSpace
