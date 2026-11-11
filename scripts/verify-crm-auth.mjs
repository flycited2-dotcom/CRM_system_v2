const base = 'http://127.0.0.1:4000/api';
const email = process.env.OWNER_EMAIL || 'owner@example.com';
const password = process.env.OWNER_PASSWORD || 'ChangeMe123!';

const login = await fetch(`${base}/auth/login`, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ email, password })
});

let payload = {};
try {
  payload = await login.json();
} catch {}

console.log(`login_status=${login.status}`);
console.log(`access_token_present=${Boolean(payload.accessToken)}`);
console.log(`refresh_token_present=${Boolean(payload.refreshToken)}`);

if (!login.ok || !payload.accessToken) {
  process.exit(1);
}

const headers = { authorization: `Bearer ${payload.accessToken}` };
for (const endpoint of ['/auth/me', '/users', '/clients', '/leads']) {
  const response = await fetch(`${base}${endpoint}`, { headers });
  let body = null;
  try {
    body = await response.json();
  } catch {}

  const count = Array.isArray(body)
    ? body.length
    : Array.isArray(body?.items)
      ? body.items.length
      : 'n/a';
  console.log(`${endpoint}_status=${response.status} count=${count}`);

  if (!response.ok) {
    process.exitCode = 1;
  }
}

const logout = await fetch(`${base}/auth/logout`, { method: 'POST', headers });
console.log(`logout_status=${logout.status}`);

if (!logout.ok) {
  process.exitCode = 1;
}
