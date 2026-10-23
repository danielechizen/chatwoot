# Leaf Admin fork

Sync-friendly sidebar integration. The dashboard and the HTTP controller speak only `Leaf::Contract`. A future adapter maps any external payload into that shape; the Vue panel does not change.

## Core files this fork touches

- `config/application.rb` — eager-loads `custom/app/controllers` and `custom/app/services` when those directories exist, as separate Zeitwerk roots.
- `config/routes.rb` — `GET customer`, `POST payment`, and `POST unblock` on `integrations/leaf`.
- `config/integration/apps.yml` — `leaf_admin` catalog entry so the generic Integration Hooks page renders the form.
- `config/locales/en.yml` — English `integration_apps.leaf_admin` copy.
- `config/locales/pt_BR.yml` — Portuguese `integration_apps.leaf_admin` copy.
- `app/javascript/dashboard/composables/useUISettings.js` — adds `leaf_customer` to the default conversation sidebar order.
- `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue` — one accordion, shown when the `leaf_admin` integration is enabled.
- `app/javascript/dashboard/i18n/locale/en/conversation.json` — English sidebar strings.
- `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json` — Portuguese sidebar strings.
- `public/dashboard/images/integrations/leaf_admin.png` — light logo.
- `public/dashboard/images/integrations/leaf_admin-dark.png` — dark logo.

## New code

- `custom/app/controllers/api/v1/accounts/integrations/leaf_controller.rb`
- `custom/app/services/leaf/client.rb`
- `custom/app/services/leaf/contract.rb`
- `custom/app/services/leaf/mock_adapter.rb`
- `custom/app/services/leaf/fixtures/customers.json` plus `pix.png` and `boleto.pdf` (encoded into the payment payload at runtime)
- `app/javascript/dashboard/api/leaf.js`
- `app/javascript/dashboard/components-next/leaf/LeafCustomerPanel.vue`

`Leaf::Client.build` returns `Leaf::MockAdapter` for now. It ignores `system_url` and `api_key`. The controller requires an enabled `Integrations::Hook` with `app_id` `leaf_admin`.

## Contact API contract

Lookup uses the existing contact fields only, in this order:

1. `custom_attributes["cpf_cnpj"]`
2. `phone_number`

There is no new contact column, no Contact model change, and no contact strong-params change. Match is exact string equality. Blank values are skipped.

## Adapters

Public client methods return `Leaf::Contract` hashes only:

- customer lookup: `found` plus `customer`, or `found: false` with `reason` `missing_identifier` or `not_found`
- payment: one of `pix`, `boleto`, or `card`
- unblock: `unblocked`, `name`, and `connection`

Do not add adapter-only keys to those payloads. Map external responses inside the adapter, then build the hash with `Leaf::Contract`.

Stable 422 codes from the controller: `leaf_admin_not_enabled`, `unknown_method`, `unknown_invoice`, `missing_identifier`, `not_found`, `connection_not_blocked`. Customer lookup stays HTTP 200 when the customer is missing.

Unblock state for the mock lives in `Rails.cache` under the account id and the matched identifier. No migration.

## Mock fixtures

| Customer | CPF/CNPJ | Phone | Profile |
| --- | --- | --- | --- |
| Fibra Alfa LTDA | `11144477735` | `+5511987654321` | FTTH online, ONU online, ativo, two invoices |
| Provedor Exemplo LTDA | `52998224725` | `+5511912345678` | FTTH offline, blocked, ONU los, suspenso, invoice `tit-1001` |
| Rádio Serra ME | `11222333000181` | `+5521988887766` | radio, ONU null, ativo, no invoices |
