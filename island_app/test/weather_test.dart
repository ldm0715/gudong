import 'package:flutter_test/flutter_test.dart';
import 'package:island_app/features/weather/weather_models.dart';

void main() {
  test('parses a weather.updated snapshot', () {
    final snapshot = WeatherSnapshot.fromJson({
      'place': '广州',
      'temp_c': 19.6,
      'kind': 'cloudy',
      'description': '阴',
      'is_day': false,
      'updated_at_ms': 1794997775244,
      'feels_like_c': 17.2,
      'humidity': 68,
      'wind_kph': 19.4,
      'high_c': 24,
      'low_c': 18,
      'hours': [
        {
          'time': '21:00',
          'temp_c': 12.4,
          'kind': 'rain',
          'description': '小雨',
          'is_day': false,
          'precip_probability': 30,
          'feels_like_c': 11.2,
        },
      ],
      'days': [
        {
          'date': '2026-11-18',
          'kind': 'partly',
          'description': '多云',
          'high_c': 24,
          'low_c': 18,
          'precip_probability': 20,
        },
        {
          'date': '2026-11-19',
          'kind': 'rain',
          'description': '小雨',
          'high_c': 19,
          'low_c': 16,
        },
      ],
    });
    expect(snapshot.place, '广州');
    expect(snapshot.roundedTemp, 20);
    expect(snapshot.kind, WeatherKind.cloudy);
    expect(snapshot.description, '阴');
    expect(snapshot.isDay, isFalse);
    expect(snapshot.feelsLikeC, 17.2);
    expect(snapshot.humidity, 68);
    expect(snapshot.windKph, 19.4);
    expect(snapshot.highC, 24);
    expect(snapshot.lowC, 18);
    expect(snapshot.hours, hasLength(1));
    expect(snapshot.hours[0].time, '21:00');
    expect(snapshot.hours[0].roundedTemp, 12);
    expect(snapshot.hours[0].kind, WeatherKind.rain);
    expect(snapshot.hours[0].isDay, isFalse);
    expect(snapshot.hours[0].precipProbability, 30);
    expect(snapshot.days, hasLength(2));
    expect(snapshot.days[0].kind, WeatherKind.partly);
    expect(snapshot.days[0].precipProbability, 20);
    expect(snapshot.days[1].kind, WeatherKind.rain);
    expect(snapshot.days[1].precipProbability, isNull);
  });

  test('parses a place search result', () {
    final place = WeatherPlace.fromJson(const {
      'name': '广州',
      'admin': '广东省',
      'country': '中国',
      'latitude': 23.11667,
      'longitude': 113.25,
      'label': '广州 · 广东省 · 中国',
    });
    expect(place.name, '广州');
    expect(place.label, '广州 · 广东省 · 中国');
    expect(place.detail, '广东省 · 中国');
    expect(place.latitude, 23.11667);
    expect(place.longitude, 113.25);
  });

  test('falls back to safe defaults for unknown values', () {
    final snapshot = WeatherSnapshot.fromJson({'kind': 'hail'});
    expect(snapshot.place, '');
    expect(snapshot.tempC, 0);
    expect(snapshot.kind, WeatherKind.cloudy);
    expect(snapshot.description, '');
    expect(snapshot.isDay, isFalse);
    expect(snapshot.feelsLikeC, isNull);
    expect(snapshot.humidity, isNull);
    expect(snapshot.hours, isEmpty);
    expect(snapshot.days, isEmpty);
  });
}
