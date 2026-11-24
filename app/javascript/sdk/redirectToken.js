const REDIRECT_PARAM = 'cw_redirect';
const OPEN_PARAM = 'cw_open';

export function readRedirectFragment(href) {
  const url = new URL(href);
  const params = new URLSearchParams(url.hash.replace(/^#/, ''));
  const token = params.get(REDIRECT_PARAM);
  const open = params.get(OPEN_PARAM) === '1';

  if (token) {
    params.delete(REDIRECT_PARAM);
  }

  const nextHash = params.toString();
  url.hash = nextHash ? `#${nextHash}` : '';

  return {
    token: token || null,
    open,
    href: url.toString(),
  };
}

export function redirectTokenUrl(baseUrl, websiteToken) {
  const url = new URL('/api/v1/widget/redirect_token', baseUrl);
  url.searchParams.set('website_token', websiteToken);
  return url.toString();
}

export async function resolveWidgetRedirect({
  baseUrl,
  websiteToken,
  authToken,
  token,
  fetchImpl = globalThis.fetch,
}) {
  const response = await fetchImpl(redirectTokenUrl(baseUrl, websiteToken), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Auth-Token': authToken,
    },
    body: JSON.stringify({ token }),
  });

  if (!response.ok) {
    return null;
  }

  return response.json();
}
