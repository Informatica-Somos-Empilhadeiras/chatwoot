import {
  isLocationMessage,
  locationOf,
  locationPreview,
  mapTiles,
  parseLocationText,
  wazeUrl,
} from '../location';

describe('location', () => {
  it('reads the location text Evolution writes, in any of its languages', () => {
    expect(
      parseLocationText(
        '*Localização:*\n\n_Latitude:_ -16.6869 \n_Longitude:_ -49.2648 \n_Nome:_ Somos Goiânia\n_Endereço:_ Av. Anhanguera, 100 \n_URL:_ https://www.google.com/maps/search/?api=1&query=-16.6869,-49.2648'
      )
    ).toEqual({
      header: null,
      latitude: -16.6869,
      longitude: -49.2648,
      name: 'Somos Goiânia',
      address: 'Av. Anhanguera, 100',
    });
    const group = parseLocationText(
      '**+55 62 99999-0003 - Marcos:**\n\n*Location:*\n\n_Latitude:_ -23.55 \n_Longitude:_ -46.63 \n_URL:_ https://maps'
    );
    expect(group).toMatchObject({
      header: '+55 62 99999-0003 - Marcos',
      latitude: -23.55,
      longitude: -46.63,
      name: '',
    });
  });

  it('keeps normal text as text', () => {
    expect(parseLocationText('*Localização:* fica na rua 10')).toBeNull();
    expect(
      parseLocationText('*Localização:*\n\n_Latitude:_ abc\n_Longitude:_ 1')
    ).toBeNull();
    expect(
      parseLocationText('*Localização:*\n\n_Latitude:_ 1\n_Longitude:_ 2\nOi')
    ).toBeNull();
  });

  it('prefers the data saved when the location went out from Chatwoot', () => {
    const props = {
      content: '*Localização:*\n\n_Latitude:_ 1 \n_Longitude:_ 2 \n',
      contentAttributes: {
        outsiderLocation: {
          latitude: -16.68,
          longitude: -49.25,
          name: 'Matriz',
          address: 'Goiânia',
        },
      },
    };
    expect(locationOf(props)).toMatchObject({
      name: 'Matriz',
      latitude: -16.68,
    });
    expect(isLocationMessage(props)).toBe(true);
    expect(isLocationMessage({ ...props, private: true })).toBe(false);
  });

  it('writes a short preview for the conversation list', () => {
    expect(
      locationPreview({
        content:
          '*Localização:*\n\n_Latitude:_ 1 \n_Longitude:_ 2 \n_Nome:_ Matriz\n',
      })
    ).toBe('📍 Matriz');
    expect(
      locationPreview({
        content: '*Location:*\n\n_Latitude:_ 1 \n_Longitude:_ 2 \n',
      })
    ).toBe('📍 Location');
    expect(locationPreview({ content: 'Oi' })).toBeNull();
  });

  it('builds the map tiles around the point and the navigation links', () => {
    const tiles = mapTiles({
      latitude: -16.6869,
      longitude: -49.2648,
      width: 288,
      height: 144,
    });
    expect(tiles.length).toBeGreaterThanOrEqual(2);
    tiles.forEach(tile => {
      expect(tile.url).toMatch(
        /^https:\/\/tile\.openstreetmap\.org\/16\/\d+\/\d+\.png$/
      );
      expect(tile.left).toBeGreaterThan(-256);
      expect(tile.left).toBeLessThan(288);
    });
    expect(wazeUrl({ latitude: 1, longitude: 2 })).toBe(
      'https://waze.com/ul?ll=1,2&navigate=yes'
    );
  });
});
