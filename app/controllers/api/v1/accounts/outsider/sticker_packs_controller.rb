# OUTSIDER: grupos de figurinhas do atendente (ver app/services/outsider/sticker_library.rb).
class Api::V1::Accounts::Outsider::StickerPacksController < Api::V1::Accounts::BaseController
  rescue_from ::Outsider::StickerLibrary::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def create
    render json: { pack: library.create_pack(params.require(:name)).picker_data }
  end

  def update
    render json: { pack: library.update_pack(params[:id], params.permit(:name, :position)).picker_data }
  end

  def destroy
    library.destroy_pack(params[:id])
    head :no_content
  end

  private

  def library
    @library ||= ::Outsider::StickerLibrary.new(user: Current.user, account: Current.account)
  end
end
