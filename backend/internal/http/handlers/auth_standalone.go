package handlers

import (
	"encoding/json"
	"html/template"
	"net/http"
	"strings"
	"time"

	"gigme/backend/internal/auth"
)

type standaloneAuthExchangeRequest struct {
	ID        int64  `json:"id"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	Username  string `json:"username"`
	PhotoURL  string `json:"photo_url"`
	AuthDate  int64  `json:"auth_date"`
	Hash      string `json:"hash"`
}

type standaloneAuthExchangeResponse struct {
	InitData string `json:"initData"`
}

var standaloneAuthTemplate = template.Must(template.New("standalone_auth").Parse(`
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>GigMe Mobile Login</title>
  <style>
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: linear-gradient(140deg, #f2f7ff 0%, #f7fbef 100%);
      color: #0f172a;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .card {
      width: 100%;
      max-width: 480px;
      background: rgba(255, 255, 255, 0.9);
      border: 1px solid rgba(15, 23, 42, 0.08);
      border-radius: 18px;
      padding: 22px;
      box-shadow: 0 14px 34px rgba(15, 23, 42, 0.09);
    }
    h1 {
      margin: 0 0 6px;
      font-size: 24px;
      line-height: 1.2;
    }
    p {
      margin: 0 0 14px;
      color: #334155;
      line-height: 1.45;
    }
    .status {
      min-height: 20px;
      margin-bottom: 12px;
      font-size: 14px;
      color: #0f766e;
    }
    .status.error {
      color: #b91c1c;
    }
    .widget {
      display: flex;
      justify-content: center;
      margin: 10px 0 8px;
    }
    textarea {
      width: 100%;
      min-height: 110px;
      padding: 10px;
      border-radius: 10px;
      border: 1px solid #cbd5e1;
      font-size: 12px;
      line-height: 1.35;
      margin-top: 10px;
    }
    button {
      margin-top: 8px;
      border: 0;
      border-radius: 10px;
      background: #0f766e;
      color: #fff;
      font-size: 14px;
      padding: 9px 12px;
      cursor: pointer;
    }
  </style>
  <script>
    (() => {
      const params = new URLSearchParams(window.location.search);
      const redirectUriParam = params.get('redirect_uri') || params.get('redirectUri') || '';
      const nativeRedirectUri = 'gigme://auth';
      let fallbackTimerId = null;

      function setStatus(message, isError) {
        const status = document.getElementById('status');
        status.textContent = message || '';
        status.classList.toggle('error', !!isError);
      }

      function buildExchangeUrl() {
        return window.location.pathname.replace(/\/+$/, '') + '/exchange';
      }

      function buildRedirectUrl(base, initData) {
        try {
          const out = new URL(base, window.location.origin);
          out.searchParams.set('initData', initData);
          return out.toString();
        } catch (error) {
          const sep = base.includes('?') ? '&' : '?';
          return base + sep + 'initData=' + encodeURIComponent(initData);
        }
      }

      function revealInitData(initData, message) {
        const output = document.getElementById('initData');
        output.value = initData;
        output.hidden = false;
        document.getElementById('copyBtn').hidden = false;
        setStatus(message, false);
      }

      function clearFallbackTimer() {
        if (fallbackTimerId == null) return;
        window.clearTimeout(fallbackTimerId);
        fallbackTimerId = null;
      }

      function openWithoutRedirectParam(initData) {
        const nativeUrl = buildRedirectUrl(nativeRedirectUri, initData);

        setStatus('Opening app…', false);
        window.location.href = nativeUrl;

        fallbackTimerId = window.setTimeout(() => {
          fallbackTimerId = null;
          if (document.visibilityState === 'hidden') return;
          revealInitData(initData, 'App did not open. Copy initData manually.');
        }, 1600);

        window.setTimeout(() => {
          if (document.visibilityState === 'hidden') return;
          revealInitData(initData, 'If redirect failed, copy initData manually.');
        }, 2600);
      }

      async function exchange(user) {
        const response = await fetch(buildExchangeUrl(), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(user),
        });
        if (!response.ok) {
          let message = 'Auth exchange failed';
          try {
            const payload = await response.json();
            if (payload && typeof payload.error === 'string' && payload.error.trim()) {
              message = payload.error.trim();
            }
          } catch (_) {}
          throw new Error(message);
        }
        const payload = await response.json();
        if (!payload || typeof payload.initData !== 'string' || !payload.initData.trim()) {
          throw new Error('Server returned empty initData');
        }
        return payload.initData.trim();
      }

      window.onTelegramAuth = async function(user) {
        try {
          setStatus('Authorizing…', false);
          const initData = await exchange(user);
          if (redirectUriParam) {
            setStatus('Redirecting back to app…', false);
            window.location.href = buildRedirectUrl(redirectUriParam, initData);
            return;
          }

          openWithoutRedirectParam(initData);
        } catch (error) {
          setStatus(error?.message || 'Authorization failed', true);
        }
      };

      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'hidden') {
          clearFallbackTimer();
        }
      });
      window.addEventListener('pagehide', clearFallbackTimer);

      window.copyInitData = async function() {
        const output = document.getElementById('initData');
        if (!output || !output.value) return;
        try {
          await navigator.clipboard.writeText(output.value);
          setStatus('initData copied.', false);
        } catch (_) {
          output.select();
          document.execCommand('copy');
          setStatus('initData copied.', false);
        }
      };
    })();
  </script>
</head>
<body>
  <div class="card">
    <h1>GigMe Mobile Login</h1>
    <p>Authorize with Telegram and return back to the app.</p>
    <div id="status" class="status"></div>
    <div class="widget">
      <script async src="https://telegram.org/js/telegram-widget.js?22"
        data-telegram-login="{{ .BotUsername }}"
        data-size="large"
        data-radius="10"
        data-request-access="write"
        data-onauth="onTelegramAuth(user)"></script>
    </div>
    <textarea id="initData" hidden readonly></textarea>
    <button id="copyBtn" type="button" hidden onclick="copyInitData()">Copy initData</button>
  </div>
</body>
</html>
`))

func (h *Handler) StandaloneAuthPage(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	botUsername := strings.TrimSpace(h.cfg.TelegramUser)
	if botUsername == "" {
		logger.Warn("action", "action", "standalone_auth_page", "status", "missing_bot_username")
		writeError(w, http.StatusServiceUnavailable, "telegram bot username is not configured")
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := standaloneAuthTemplate.Execute(w, map[string]string{
		"BotUsername": botUsername,
	}); err != nil {
		logger.Error("action", "action", "standalone_auth_page", "status", "render_error", "error", err)
	}
}

func (h *Handler) StandaloneAuthExchange(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)

	var req standaloneAuthExchangeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "standalone_auth_exchange", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	user, err := auth.ValidateLoginWidgetPayload(auth.LoginWidgetPayload{
		ID:        req.ID,
		FirstName: strings.TrimSpace(req.FirstName),
		LastName:  strings.TrimSpace(req.LastName),
		Username:  strings.TrimSpace(req.Username),
		PhotoURL:  strings.TrimSpace(req.PhotoURL),
		AuthDate:  req.AuthDate,
		Hash:      strings.TrimSpace(req.Hash),
	}, h.cfg.TelegramToken, 24*time.Hour)
	if err != nil {
		logger.Warn("action", "action", "standalone_auth_exchange", "status", "invalid_telegram_login", "error", err)
		writeError(w, http.StatusUnauthorized, "invalid telegram login data")
		return
	}

	initData, err := auth.BuildWebAppInitData(user, h.cfg.TelegramToken, time.Unix(req.AuthDate, 0).UTC())
	if err != nil {
		logger.Error("action", "action", "standalone_auth_exchange", "status", "build_init_data_failed", "error", err)
		writeError(w, http.StatusInternalServerError, "failed to prepare initData")
		return
	}

	writeJSON(w, http.StatusOK, standaloneAuthExchangeResponse{InitData: initData})
}
