# Leaf Admin fork

Sync-friendly sidebar integration. The dashboard and the HTTP controller speak only `Leaf::Contract`. A future adapter maps any external payload into that shape; the Vue panel does not change.

## Core files this fork touches

- `config/application.rb` — eager-loads `custom/app/controllers` and `custom/app/services` when those directories exist, as separate Zeitwerk roots. While the application class loads, it requires `custom/lib/custom.rb` so `module Custom` exists before `prepend_mod_with`, then requires `custom/config/initializers/branding.rb`. That directory is not an autoload path. The require is the seam.
- `app/views/widgets/show.html.erb` — `disableBranding: true`. The widget hides the Chatwoot mark without turning on the `disable_branding` feature. The help center footer is unchanged.
- `config/initializers/01_inject_enterprise_edition_module.rb` — `const_get_maybe_false` must return nil, not false, when the receiver is not a module or the constant is missing. `&&` used to return boolean false, and the next lookup called `const_defined?` on that false. `const_defined?(name, false)` does not trigger Zeitwerk, so `Enterprise` can be missing at that moment too.
- `config/routes.rb` — Leaf routes under `integrations/leaf`: `GET customer`, `GET invoices`, `POST payment`, `POST unblock`, `POST disconnect`, `POST clear_mac`, `POST test`.
- `config/integration/apps.yml` — `leaf_admin` catalog entry. `visible_properties` stays `system_url` only, so the API key is never returned to the browser.
- `app/controllers/api/v1/accounts/integrations/hooks_controller.rb` — on `PATCH` for `leaf_admin`, a blank `api_key` keeps the stored key. A new key replaces it.
- `config/locales/en.yml` — English `integration_apps.leaf_admin` copy.
- `config/locales/pt_BR.yml` — Portuguese `integration_apps.leaf_admin` copy.
- `app/javascript/dashboard/composables/useUISettings.js` — `leaf_customer` is the first default sidebar item. A saved order that omits it gets the item inserted at the front. The contact sidebar is open when `is_contact_sidebar_open` is unset, and a saved `false` stays closed.
- `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue` — one accordion, shown when the `leaf_admin` integration is enabled. The accordion is open when `is_leaf_customer_open` is unset.
- `app/javascript/dashboard/routes/dashboard/settings/integrations/LeafHookSettings.vue` — edits the saved system URL and API key, and tests the connection.
- `app/javascript/dashboard/i18n/locale/en/conversation.json` — English sidebar strings.
- `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json` — Portuguese sidebar strings.
- `public/dashboard/images/integrations/leaf_admin.png` — light logo.
- `public/dashboard/images/integrations/leaf_admin-dark.png` — dark logo.

## New code

- `custom/lib/custom.rb` — empty `module Custom`, required at boot. Leaf code stays under `Leaf::`. The initializer must still return nil rather than false when a `Custom::` or `Enterprise::` constant is missing.
- `custom/app/services/custom/branding.rb` — `Custom::Branding.apply!`
- `custom/config/initializers/branding.rb` — applies branding once per process and prepends the plan reset hook
- `custom/bin/check_seams.rb` — checks the fork seams after an upstream merge
- `public/brand-assets/leaf/logo.svg`, `logo_dark.svg`, and `logo_thumbnail.svg` — Leaf Agent marks. The original files in `public/brand-assets/` stay untouched.
- `custom/app/controllers/api/v1/accounts/integrations/leaf_controller.rb`
- `custom/app/services/leaf/client.rb`
- `custom/app/services/leaf/http_adapter.rb`
- `custom/app/services/leaf/contract.rb`
- `custom/app/services/leaf/mock_adapter.rb`
- `custom/bin/publish-image.sh`
- `custom/app/services/leaf/fixtures/customers.json` plus `pix.png` and `boleto.pdf` (encoded into the payment payload at runtime)
- `app/javascript/dashboard/api/leaf.js`
- `app/javascript/dashboard/components-next/leaf/LeafCustomerPanel.vue`

`Leaf::Client.build` uses `Leaf::HttpAdapter` (`system_url` + `/api/v2`, header `x-auth-header`). TLS verification is off only for those Leaf requests. `Leaf::MockAdapter` stays in the repo and is not used for an enabled hook. `POST test` calls `GET /integrations/contracts?limit=1`. The controller requires an enabled `Integrations::Hook` with `app_id` `leaf_admin`.

Publish with `bash custom/bin/publish-image.sh local` (`localhost:5000/leaf-agent:latest` and `:<sha>`) or `bash custom/bin/publish-image.sh remote` (`$LEAF_REGISTRY/leaf-agent`, same tags).

## Contact API contract

Lookup uses the existing contact fields only, digits only, in this order:

1. `custom_attributes["cpf_cnpj"]`
2. `phone_number`

There is no new contact column, no Contact model change, and no contact strong-params change. Blank values are skipped. A selected `contractId` is checked against that contact before Leaf is called for the connection or the delayed invoices.

## Adapters

Public client methods return `Leaf::Contract` hashes only. Omit a key when the adapter has no value. Map the Leaf response inside `Leaf::HttpAdapter` and `Leaf::Client`, then build the hash with `Leaf::Contract`. The PPPoE password never leaves that mapping.

`Leaf::HttpAdapter` calls `system_url` + `/api/v2` with header `x-auth-header`. TLS verification is off only for those requests (`verify: false`), and they do not follow redirects. Other Chatwoot HTTP clients keep verification on.

Customer lookup (`GET customer`) searches contracts by document digits, then phone digits. It returns `found` plus `customer`, or HTTP 200 `found: false` with `reason` `missing_identifier` or `not_found`. `customer` has `name`, `registration_status` (`active` → `ativo`, `blocked` → `bloqueado`), `contracts` (`number`, `label`), and `connection` when the contract has a `connectionId`. A blank `contract_number` uses the first contract. An id that is not in that contact's list is 422 `not_found`.

`connection.username` is the PPPoE login. `blocked` follows the contract status. `last_log` is `auth.message` when present. ONU is included only for `ftth` when `gpon` has a serial and status: optional `rx_dbm`, and `error` when offline and the alarm is not `ND`. Without `connectionId`, the panel hides the connection, the ONU, and the three buttons.

Invoices (`GET invoices`) require `contract_number`. The server checks that id, then loads delayed billets (limit 5, due date ascending). `payment_methods` comes from that response (`pix`, `bankSlip`, `creditCard`). `POST payment` checks the billet id and the method, then returns PIX (`copy_paste`, `image_base64`), boleto (`pdf_base64` and/or `payment_url`), or card (`payment_url`).

Unblock calls extend, disconnect calls disconnect with `force: false`, and clear MAC calls clear-mac. Each returns a small contract object. The controller writes a private note with `detailDescription` on success and on error, sent as the current user. The panel refreshes and does not write that note.

`POST test` calls `GET /integrations/contracts?limit=1` and returns `{ "ok": true }` or 422 `invalid_credentials`. The request may include the system URL and API key currently in the form. A blank field falls back to the saved hook, so a test after save still uses both stored values. The live servlet sends `statusCode` and `detailCode` as names (`OK`, `ERROR`, `BAD_TOKEN`, `FORBIDDEN`); integer codes from the OpenAPI file are accepted too.

Stable 422 codes from the controller: `leaf_admin_not_enabled`, `unknown_method`, `unknown_invoice`, `missing_identifier`, `not_found`, `invalid_credentials`, `leaf_request_failed`. A `contract_number` that is not a digit string is also 422.

`Leaf::MockAdapter` stays in the repo and is not used for an enabled hook. Its cache, when the class is used directly, still lives in `Rails.cache`. No migration.

## Branding

`Custom::Branding.apply!` writes `INSTALLATION_NAME` and `BRAND_NAME` when the stored value is blank, `Chatwoot`, or `Leaf`. The new value is `Leaf Agent`. Any other stored name stays. Logo paths are written only when blank or still the Chatwoot path. A later manual logo path stays.

| Key | Leaf Agent value | Values that get replaced |
| --- | --- | --- |
| `INSTALLATION_NAME` | `Leaf Agent` | blank, `Chatwoot`, or `Leaf` |
| `BRAND_NAME` | `Leaf Agent` | blank, `Chatwoot`, or `Leaf` |
| `LOGO` | `/brand-assets/leaf/logo.svg` | blank or `/brand-assets/logo.svg` |
| `LOGO_DARK` | `/brand-assets/leaf/logo_dark.svg` | blank or `/brand-assets/logo_dark.svg` |
| `LOGO_THUMBNAIL` | `/brand-assets/leaf/logo_thumbnail.svg` | blank or `/brand-assets/logo_thumbnail.svg` |

The boot initializer calls `apply!`. Saving a config clears `GlobalConfig` through the existing `after_commit`. If the database or the `installation_configs` table is missing (`db:create`), that boot call skips only `ActiveRecord::NoDatabaseError` and a missing-relation `ActiveRecord::StatementInvalid`. Other errors propagate.

Asset precompile skips that boot call when the process is `rake` and ARGV includes `assets:precompile`, and does not query `InstallationConfig`.

On the community plan, `Internal::ReconcilePlanConfigService#reconcile_premium_config` copies the Chatwoot premium defaults back. The prepended module calls `super`, then `Custom::Branding.apply!`, so the name becomes Leaf Agent again and the logos return to the Leaf paths. The product name is not copied into Vue.

The widget seam is the literal `disableBranding: true` in `app/views/widgets/show.html.erb`.

After every upstream merge, run:

```sh
ruby custom/bin/check_seams.rb
```

The script is not part of a GitHub workflow. It exits 0 when every seam snippet is present, and exits 1 after printing each missing path and snippet.

## Mock fixtures

| Customer | CPF/CNPJ | Phone | Profile |
| --- | --- | --- | --- |
| Fibra Alfa LTDA | `11144477735` | `+5511987654321` | FTTH online, last log success, ONU online with serial and RX, ativo, contracts `1001` (PIX and boleto, `tit-2001`, `tit-2002`) and `1002` (card, `tit-2003`) |
| Provedor Exemplo LTDA | `52998224725` | `+5511912345678` | FTTH offline, blocked, password last log, ONU offline with serial and error text, suspenso, contract `2001`, overdue invoices including `tit-1001` |
| Rádio Serra ME | `11222333000181` | `+5521988887766` | radio, no last log, no ONU, no contracts, no invoices, ativo |
