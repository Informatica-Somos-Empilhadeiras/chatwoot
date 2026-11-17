# OUTSIDER: foto do perfil de uma pessoa do Teams por endereço assinado (Outsider::Teams::Graph::Photo). Sem foto = 404,
# e a tela mostra as iniciais.
class Outsider::TeamsPhotosController < ActionController::API
  def show
    data = Outsider::Teams::Graph::Photo.read(params[:t])
    return head(:not_found) unless data

    link = Outsider::TeamsLink.find_by(id: data['l'])
    return head(:not_found) unless link&.status == 'active'

    photo = Outsider::Teams::Graph::Photo.new(link).fetch(data['u'])
    return head(:not_found) unless photo

    response.headers['Cache-Control'] = 'private, max-age=86400'
    send_data photo[:body], type: photo[:content_type].presence || 'image/jpeg', disposition: 'inline'
  end
end
