import '../models/activity_state.dart';
import '../models/location_fix.dart';

/// Построитель треков с правилами добавления точек и упрощением
class TrackBuilder {
  // Параметры для разных режимов движения
  static const double _walkingDistanceThreshold = 50.0; // метры
  static const double _vehicleDistanceThreshold = 200.0; // метры
  static const double _walkingHeadingThreshold = 30.0; // градусы
  static const double _vehicleHeadingThreshold = 25.0; // градусы
  static const Duration _walkingTimeFallback = Duration(seconds: 30);
  static const Duration _vehicleTimeFallback = Duration(seconds: 15);
  
  // Параметры упрощения (Douglas-Peucker)
  static const double _walkingSimplificationTolerance = 15.0; // метры
  static const double _vehicleSimplificationTolerance = 30.0; // метры
  
  List<LocationFix> _currentPoints = [];
  LocationFix? _lastAcceptedPoint;
  DateTime? _lastAcceptedTime;
  ActivityState _currentState = ActivityState.still;
  
  /// Добавить точку в трек
  /// Возвращает true, если точка была принята
  bool addPoint(LocationFix point, ActivityState state) {
    _currentState = state;
    
    // Первая точка всегда принимается
    if (_lastAcceptedPoint == null) {
      _lastAcceptedPoint = point;
      _lastAcceptedTime = point.timestamp;
      _currentPoints.add(point);
      return true;
    }
    
    // Проверяем правила добавления
    final distance = point.distanceTo(_lastAcceptedPoint!);
    final timeSinceLast = point.timestamp.difference(_lastAcceptedTime!);
    
    // Правило 1: Дистанция
    final distanceThreshold = _getDistanceThreshold(state);
    if (distance >= distanceThreshold) {
      _acceptPoint(point);
      return true;
    }
    
    // Правило 2: Изменение курса
    if (_lastAcceptedPoint!.heading != null && point.heading != null) {
      final headingChange = _calculateHeadingChange(
        _lastAcceptedPoint!.heading!,
        point.heading!,
      );
      final headingThreshold = _getHeadingThreshold(state);
      
      if (headingChange.abs() >= headingThreshold) {
        _acceptPoint(point);
        return true;
      }
    }
    
    // Правило 3: Fallback по времени
    final timeFallback = _getTimeFallback(state);
    if (timeSinceLast >= timeFallback && distance > 10.0) {
      // Принимаем только если есть минимальное движение
      _acceptPoint(point);
      return true;
    }
    
    return false;
  }
  
  void _acceptPoint(LocationFix point) {
    _lastAcceptedPoint = point;
    _lastAcceptedTime = point.timestamp;
    _currentPoints.add(point);
  }
  
  /// Получить упрощенный полилайн для сегмента
  List<LocationFix> getSimplifiedPolyline() {
    if (_currentPoints.length <= 2) return List.from(_currentPoints);
    
    final tolerance = _getSimplificationTolerance(_currentState);
    return _douglasPeucker(_currentPoints, tolerance);
  }
  
  /// Получить текущие точки (без упрощения)
  List<LocationFix> getCurrentPoints() => List.from(_currentPoints);
  
  /// Очистить текущий трек
  void clear() {
    _currentPoints.clear();
    _lastAcceptedPoint = null;
    _lastAcceptedTime = null;
  }
  
  /// Завершить сегмент и получить финальный полилайн
  List<LocationFix> finalize() {
    final simplified = getSimplifiedPolyline();
    clear();
    return simplified;
  }
  
  double _getDistanceThreshold(ActivityState state) {
    switch (state) {
      case ActivityState.walking:
        return _walkingDistanceThreshold;
      case ActivityState.inVehicle:
        return _vehicleDistanceThreshold;
      case ActivityState.still:
        return 10.0; // минимальный порог для стояния
    }
  }
  
  double _getHeadingThreshold(ActivityState state) {
    switch (state) {
      case ActivityState.walking:
        return _walkingHeadingThreshold;
      case ActivityState.inVehicle:
        return _vehicleHeadingThreshold;
      case ActivityState.still:
        return 45.0; // более высокий порог для стояния
    }
  }
  
  Duration _getTimeFallback(ActivityState state) {
    switch (state) {
      case ActivityState.walking:
        return _walkingTimeFallback;
      case ActivityState.inVehicle:
        return _vehicleTimeFallback;
      case ActivityState.still:
        return const Duration(minutes: 1);
    }
  }
  
  double _getSimplificationTolerance(ActivityState state) {
    switch (state) {
      case ActivityState.walking:
        return _walkingSimplificationTolerance;
      case ActivityState.inVehicle:
        return _vehicleSimplificationTolerance;
      case ActivityState.still:
        return 10.0;
    }
  }
  
  /// Вычисляет изменение курса (в градусах, -180 до 180)
  double _calculateHeadingChange(double heading1, double heading2) {
    double diff = heading2 - heading1;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }
  
  /// Алгоритм Douglas-Peucker для упрощения полилинии
  List<LocationFix> _douglasPeucker(
    List<LocationFix> points,
    double tolerance,
  ) {
    if (points.length <= 2) return List.from(points);
    
    // Находим точку с максимальным отклонением
    double maxDistance = 0.0;
    int maxIndex = 0;
    
    final first = points.first;
    final last = points.last;
    
    for (int i = 1; i < points.length - 1; i++) {
      final distance = _perpendicularDistance(points[i], first, last);
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }
    
    // Если максимальное отклонение больше допуска, рекурсивно упрощаем
    if (maxDistance > tolerance) {
      // Рекурсивно упрощаем левую и правую части
      final leftPart = _douglasPeucker(
        points.sublist(0, maxIndex + 1),
        tolerance,
      );
      final rightPart = _douglasPeucker(
        points.sublist(maxIndex),
        tolerance,
      );
      
      // Объединяем результаты (убираем дубликат в точке maxIndex)
      return [...leftPart, ...rightPart.sublist(1)];
    } else {
      // Все точки между first и last можно удалить
      return [first, last];
    }
  }
  
  /// Вычисляет перпендикулярное расстояние от точки до линии
  double _perpendicularDistance(
    LocationFix point,
    LocationFix lineStart,
    LocationFix lineEnd,
  ) {
    // Используем формулу для расстояния от точки до отрезка
    final dx = lineEnd.longitude - lineStart.longitude;
    final dy = lineEnd.latitude - lineStart.latitude;
    
    if (dx == 0 && dy == 0) {
      // Линия - это точка
      return point.distanceTo(lineStart);
    }
    
    final t = ((point.longitude - lineStart.longitude) * dx +
            (point.latitude - lineStart.latitude) * dy) /
        (dx * dx + dy * dy);
    
    // Ограничиваем t в пределах [0, 1]
    final clampedT = t.clamp(0.0, 1.0);
    
    // Точка на линии, ближайшая к point
    final closestLon = lineStart.longitude + clampedT * dx;
    final closestLat = lineStart.latitude + clampedT * dy;
    
    final closestPoint = LocationFix(
      latitude: closestLat,
      longitude: closestLon,
      timestamp: point.timestamp,
    );
    
    return point.distanceTo(closestPoint);
  }
}

