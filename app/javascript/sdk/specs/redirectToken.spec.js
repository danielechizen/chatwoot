import {
  readRedirectFragment,
  redirectTokenUrl,
  resolveWidgetRedirect,
} from '../redirectToken';

describe('readRedirectFragment', () => {
  it('reads cw_redirect, strips only that param, and keeps cw_open=1', () => {
    const href = 'https://shop.example/help#cw_redirect=opaque-token&cw_open=1';

    expect(readRedirectFragment(href)).toEqual({
      token: 'opaque-token',
      open: true,
      href: 'https://shop.example/help#cw_open=1',
    });
  });

  it('keeps cw_open when it comes before the token', () => {
    const href = 'https://shop.example/help#cw_open=1&cw_redirect=abc';

    expect(readRedirectFragment(href).href).toBe(
      'https://shop.example/help#cw_open=1'
    );
    expect(readRedirectFragment(href).open).toBe(true);
  });

  it('does not treat another open value as a request to open', () => {
    const href = 'https://shop.example/help#cw_redirect=abc&cw_open=0';
    const result = readRedirectFragment(href);

    expect(result.token).toBe('abc');
    expect(result.open).toBe(false);
    expect(result.href).toBe('https://shop.example/help#cw_open=0');
  });

  it('leaves the URL alone when the token is absent', () => {
    const href = 'https://shop.example/help#cw_open=1';

    expect(readRedirectFragment(href)).toEqual({
      token: null,
      open: true,
      href,
    });
  });
});

describe('resolveWidgetRedirect', () => {
  it('posts only the opaque token', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ widget_auth_token: 'session' }),
    });

    const result = await resolveWidgetRedirect({
      baseUrl: 'https://chat.example',
      websiteToken: 'site-token',
      authToken: 'widget-session',
      token: 'opaque-token',
      fetchImpl,
    });

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, options] = fetchImpl.mock.calls[0];
    expect(url).toBe(redirectTokenUrl('https://chat.example', 'site-token'));
    expect(url).toContain('/api/v1/widget/redirect_token');
    expect(options.method).toBe('POST');
    expect(options.headers['X-Auth-Token']).toBe('widget-session');
    expect(JSON.parse(options.body)).toEqual({ token: 'opaque-token' });
    expect(result).toEqual({ widget_auth_token: 'session' });
  });

  it('returns null when the token was already used', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({ ok: false, status: 404 });

    const result = await resolveWidgetRedirect({
      baseUrl: 'https://chat.example',
      websiteToken: 'site-token',
      authToken: 'widget-session',
      token: 'used',
      fetchImpl,
    });

    expect(result).toBeNull();
  });
});
