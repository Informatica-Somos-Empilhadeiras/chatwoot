/* global axios */
// OUTSIDER: aparência da conta (ver app/controllers/api/v1/accounts/outsider/brandings_controller.rb)
import ApiClient from '../ApiClient';

class BrandingAPI extends ApiClient {
  constructor() {
    super('outsider/branding', { accountScoped: true });
  }

  update(formData) {
    return axios.patch(this.url, formData);
  }
}

export default new BrandingAPI();
