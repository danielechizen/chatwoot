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
- `public/brand-assets/leaf/logo.svg`, `logo_dark.svg`, and `logo_thumbnail.svg` — Leaf marks. The original files in `public/brand-assets/` stay untouched.
- `custom/app/controllers/api/v1/accounts/integrations/leaf_controller.rb`
- `custom/app/services/leaf/client.rb`
- `custom/app/services/leaf/contract.rb`
- `custom/app/services/leaf/mock_adapter.rb`
- `custom/app/services/leaf/fixtures/customers.json` plus `pix.png` and `boleto.pdf` (encoded into the payment payload at runtime)
- `app/javascript/dashboard/api/leaf.js`
- `app/javascript/dashboard/components-next/leaf/LeafCustomerPanel.vue`

`Leaf::Client.build` returns `Leaf::MockAdapter`. Customer, invoice, payment, and connection actions do not call the external system. `POST test` reads the enabled hook and succeeds only when `system_url` and `api_key` are both present. The controller requires an enabled `Integrations::Hook` with `app_id` `leaf_admin`.

## Contact API contract

Lookup uses the existing contact fields only, in this order:

1. `custom_attributes["cpf_cnpj"]`
2. `phone_number`

There is no new contact column, no Contact model change, and no contact strong-params change. Match is exact string equality. Blank values are skipped.

## Adapters

Public client methods return `Leaf::Contract` hashes only. Omit a key when the adapter has no value.

Customer lookup (`GET customer`) is `found` plus `customer`, or `found: false` with `reason` `missing_identifier` or `not_found`. `customer` has `name`, `registration_status`, and `connection`. It does not include open invoices. `connection` may include `username` and `last_log`. `onu` is present only for `ftth` when the adapter has one: `serial`, `status` (`online` or `offline`), optional `rx_dbm`, and optional `error` when offline. `contracts` is optional. Each contract has `number`, `label`, and `payment_methods` (`pix`, `boleto`, `card`).

Invoices (`GET invoices?conversation_id=&contract_number=`): `contract_number` is optional. The response has `payment_methods`, `open_invoices` (at most 5, `due_on` ascending, the most overdue), and `contract_number` when the request named one or every returned invoice belongs to the same contract. With no `contract_number`, invoices are taken across contracts and `payment_methods` is the intersection of the methods for the contracts in that result. `POST payment` returns 422 `unknown_method` when the method is not available for that invoice's contract.

Unblock, disconnect, and clear MAC return a small contract object and update the mock cache so the next customer fetch shows the change. Disconnect sets connection `status` to `offline` and `last_log` to `Desconectado pelo atendente`. Clear MAC succeeds even though the customer payload does not display a MAC. Unblock still returns `unblocked`, `name`, and `connection`.

`POST test` returns `{ "ok": true }` or 422 `invalid_credentials`.

Do not add adapter-only keys to those payloads. Map external responses inside the adapter, then build the hash with `Leaf::Contract`.

Stable 422 codes from the controller: `leaf_admin_not_enabled`, `unknown_method`, `unknown_invoice`, `missing_identifier`, `not_found`, `connection_not_blocked`, `invalid_credentials`. A `contract_number` that is not a string is also 422. Customer lookup stays HTTP 200 when the customer is missing.

Connection changes for the mock live in `Rails.cache` under the account id and the matched identifier. No migration.

## Branding

`Custom::Branding.apply!` writes these `InstallationConfig` keys when the stored value is blank or still the Chatwoot default. A later manual value that is neither blank nor that default is kept.

| Key | Leaf value | Default that gets replaced |
| --- | --- | --- |
| `INSTALLATION_NAME` | `Leaf` | `Chatwoot` |
| `BRAND_NAME` | `Leaf` | `Chatwoot` |
| `LOGO` | `/brand-assets/leaf/logo.svg` | `/brand-assets/logo.svg` |
| `LOGO_DARK` | `/brand-assets/leaf/logo_dark.svg` | `/brand-assets/logo_dark.svg` |
| `LOGO_THUMBNAIL` | `/brand-assets/leaf/logo_thumbnail.svg` | `/brand-assets/logo_thumbnail.svg` |

The boot initializer calls `apply!`. Saving a config clears `GlobalConfig` through the existing `after_commit`. If the database or the `installation_configs` table is missing (`db:create`), that boot call skips only `ActiveRecord::NoDatabaseError` and a missing-relation `ActiveRecord::StatementInvalid`. Other errors propagate.

On the community plan, `Internal::ReconcilePlanConfigService#reconcile_premium_config` copies the Chatwoot premium defaults back. The prepended module calls `super`, then `Custom::Branding.apply!`, so those five keys become Leaf again. The word Leaf is not copied into Vue.

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
