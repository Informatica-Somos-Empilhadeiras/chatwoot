// OUTSIDER: endereços dos quadros do Google Maps (Street View e mapa de cima, sem satélite)
import { streetViewUrl, topMapUrl, hasPoint } from '../maps';

describe('maps helper', () => {
  it('builds the Street View and the street map of a point', () => {
    const place = { key: 'AIzaKEY', latitude: -16.68, longitude: -49.25 };
    expect(streetViewUrl(place)).toBe(
      'https://www.google.com/maps/embed/v1/streetview?key=AIzaKEY&location=-16.68,-49.25&fov=80&language=pt-BR&region=BR'
    );
    expect(topMapUrl(place)).toContain(
      '/place?key=AIzaKEY&q=-16.68%2C-49.25&zoom=18&maptype=roadmap'
    );
  });

  it('uses the address when there is no point', () => {
    const url = topMapUrl({ key: 'K', latitude: null, query: 'Rua 10, 250' });
    expect(url).toContain('q=Rua%2010%2C%20250');
    expect(hasPoint({ latitude: null, longitude: null })).toBe(false);
    expect(hasPoint({ latitude: 0, longitude: -49 })).toBe(true);
  });
});
