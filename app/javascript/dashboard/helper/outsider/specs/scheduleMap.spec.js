// OUTSIDER (Maps): agrupamento dos pins e ordem das paradas da rota
import { clusterize, orderStops, distanceKm } from '../scheduleMap';

describe('schedule map helpers', () => {
  it('groups nearby points by screen distance', () => {
    const points = [
      { id: 1, latitude: 0, longitude: 0, x: 10, y: 10 },
      { id: 2, latitude: 0, longitude: 0, x: 20, y: 30 },
      { id: 3, latitude: 0, longitude: 0, x: 300, y: 300 },
    ];
    const groups = clusterize(points, point => point, 56);
    expect(groups.map(group => group.points.map(p => p.id))).toEqual([
      [1, 2],
      [3],
    ]);
  });

  it('keeps fixed times in order and fits the untimed stop where the path grows least', () => {
    const a = { id: 'a', latitude: -16.6, longitude: -49.2, start: '09:00' };
    const c = { id: 'c', latitude: -16.6, longitude: -49.0, start: '14:00' };
    const b = { id: 'b', latitude: -16.6, longitude: -49.1, all_day: true };
    expect(orderStops([c, b, a]).map(stop => stop.id)).toEqual(['a', 'b', 'c']);
    expect(Math.round(distanceKm(a, c))).toBe(21);
  });
});
