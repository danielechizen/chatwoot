class Api::V1::Accounts::RedirectTokensController < Api::V1::Accounts::BaseController
  wrap_parameters format: []

  before_action :check_admin_authorization?

  def create
    result = RedirectTokens::Issuer.new(
      account: Current.account,
      user: Current.user,
      params: issue_params
    ).perform

    if result.success?
      render json: { token: result.token, expires_in: result.expires_in, website_url: result.website_url }
    else
      render json: { error: result.error }, status: result.error_status
    end
  end

  private

  def issue_params
    params.permit(:inbox_id, :identifier, :contact_id, :message, :ttl_seconds, :origin_display_id)
  end
end
