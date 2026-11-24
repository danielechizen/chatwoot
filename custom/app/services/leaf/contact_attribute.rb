class Leaf::ContactAttribute
  KEY = 'cpf_cnpj'
  DISPLAY_NAME = 'CPF/CNPJ'

  def self.ensure!(account)
    account.custom_attribute_definitions.create_with(
      attribute_display_name: DISPLAY_NAME,
      attribute_display_type: :text
    ).find_or_create_by!(
      attribute_key: KEY,
      attribute_model: :contact_attribute
    )
  rescue ActiveRecord::RecordNotUnique
    account.custom_attribute_definitions.find_by!(
      attribute_key: KEY,
      attribute_model: :contact_attribute
    )
  end
end
