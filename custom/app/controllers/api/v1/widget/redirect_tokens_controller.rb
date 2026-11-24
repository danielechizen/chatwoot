class Api::V1::Widget::RedirectTokensController < Api::V1::Widget::BaseController
  def create
    result = RedirectTokens::Resolver.new(
      account: @current_account,
      web_widget: @web_widget,
      contact: @contact,
      contact_inbox: @contact_inbox,
      token: permitted_params[:token]
    ).perform

    if result.nil?
      render json: { error: 'invalid_token' }, status: :not_found
      return
    end

    render json: { widget_auth_token: result.auth_token }
  end

  private

  def permitted_params
    params.permit(:website_token, :token)
  end
end
