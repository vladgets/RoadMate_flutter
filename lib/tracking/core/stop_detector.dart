import 'dart:async';
import 'dart:math' as math;
import '../models/activity_state.dart';
import '../models/location_fix.dart';

/// Событие подтверждения остановки
class StopConfirmedEvent {
  final String stopId;
  final LocationFix anchor;
  final DateTime tStart;
  final DateTime tConfirm;
  final double confidence;
  
  StopConfirmedEvent({
    required this.stopId,
    required this.anchor,
    required this.tStart,
    required this.tConfirm,
    required this.confidence,
  });
}

/// Событие завершения остановки
class StopEndedEvent {
  final String stopId;
  final DateTime tEnd;
  
  StopEndedEvent({
    required this.stopId,
    required this.tEnd,
  });
}

/// Детектор остановок с вычислением anchor
class StopDetector {
  final StreamController<StopConfirmedEvent> _stopConfirmedController = 
      StreamController<StopConfirmedEvent>.broadcast();
  final StreamController<StopEndedEvent> _stopEndedController = 
      StreamController<StopEndedEvent>.broadcast();
  
  Stream<StopConfirmedEvent> get stopConfirmedStream => _stopConfirmedController.stream;
  Stream<StopEndedEvent> get stopEndedStream => _stopEndedController.stream;
  
  // Параметры детекции
  static const Duration _stopAcquisitionWindow = Duration(seconds: 20);
  static const Duration _stopConfirmationDuration = Duration(minutes: 2);
  static const Duration _vehicleStopConfirmationDuration = Duration(minutes: 3);
  static const double _stopRadius = 40.0; // метры
  static const double _maxAccuracyForAnchor = 80.0; // метры
  static const int _minPointsForAnchor = 3;
  static const int _maxPointsForAnchor = 8;
  
  bool _isInStopAcquisition = false;
  DateTime? _stopStartTime;
  LocationFix? _stopAnchorCandidate;
  List<LocationFix> _acquisitionPoints = [];
  Timer? _acquisitionTimer;
  Timer? _confirmationTimer;
  String? _currentStopId;
  ActivityState? _stateBeforeStop;
  
  /// Обработать переход в состояние STILL
  void onStateChangedToStill(ActivityState previousState, DateTime timestamp) {
    if (_isInStopAcquisition) return; // Уже в процессе
    
    _stateBeforeStop = previousState;
    _stopStartTime = timestamp;
    _currentStopId = 'stop_${timestamp.millisecondsSinceEpoch}';
    _isInStopAcquisition = true;
    _acquisitionPoints.clear();
    
    // Запускаем окно захвата
    _acquisitionTimer?.cancel();
    _acquisitionTimer = Timer(_stopAcquisitionWindow, () {
      _finalizeAcquisition();
    });
  }
  
  /// Добавить точку локации во время окна захвата
  void addLocationPoint(LocationFix location) {
    if (!_isInStopAcquisition) return;
    
    // Фильтруем точки с плохой точностью
    if (location.accuracy != null && location.accuracy! > _maxAccuracyForAnchor) {
      return;
    }
    
    _acquisitionPoints.add(location);
    
    // Если набрали достаточно точек, можно завершить окно раньше
    if (_acquisitionPoints.length >= _maxPointsForAnchor) {
      _acquisitionTimer?.cancel();
      _finalizeAcquisition();
    }
  }
  
  void _finalizeAcquisition() {
    if (_acquisitionPoints.isEmpty || _acquisitionPoints.length < _minPointsForAnchor) {
      _reset();
      return;
    }
    
    // Вычисляем anchor
    _stopAnchorCandidate = _calculateAnchor(_acquisitionPoints);
    
    if (_stopAnchorCandidate == null) {
      _reset();
      return;
    }
    
    // Запускаем таймер подтверждения
    final confirmationDuration = _stateBeforeStop == ActivityState.inVehicle
        ? _vehicleStopConfirmationDuration
        : _stopConfirmationDuration;
    
    _confirmationTimer?.cancel();
    _confirmationTimer = Timer(confirmationDuration, () {
      _confirmStop();
    });
  }
  
  /// Обработать обновление локации для проверки выхода из радиуса
  void onLocationUpdate(LocationFix location) {
    if (_stopAnchorCandidate == null || _currentStopId == null) return;
    
    final distance = location.distanceTo(_stopAnchorCandidate!);
    
    // Если вышли за пределы радиуса, завершаем остановку
    if (distance > _stopRadius) {
      _endStop(DateTime.now());
    }
  }
  
  /// Обработать переход из состояния STILL
  void onStateChangedFromStill(ActivityState newState, DateTime timestamp) {
    if (_currentStopId != null && _stopAnchorCandidate != null) {
      _endStop(timestamp);
    } else {
      _reset();
    }
  }
  
  void _confirmStop() {
    if (_stopAnchorCandidate == null || 
        _stopStartTime == null || 
        _currentStopId == null) {
      return;
    }
    
    // Вычисляем confidence на основе количества точек и их точности
    final confidence = _calculateConfidence(_acquisitionPoints);
    
    final event = StopConfirmedEvent(
      stopId: _currentStopId!,
      anchor: _stopAnchorCandidate!,
      tStart: _stopStartTime!,
      tConfirm: DateTime.now(),
      confidence: confidence,
    );
    
    _stopConfirmedController.add(event);
    
    // Очищаем таймеры, но оставляем остановку активной
    _acquisitionTimer?.cancel();
    _confirmationTimer?.cancel();
  }
  
  void _endStop(DateTime endTime) {
    if (_currentStopId == null) return;
    
    final stopId = _currentStopId!;
    _reset();
    
    final event = StopEndedEvent(
      stopId: stopId,
      tEnd: endTime,
    );
    
    _stopEndedController.add(event);
  }
  
  void _reset() {
    _isInStopAcquisition = false;
    _stopStartTime = null;
    _stopAnchorCandidate = null;
    _acquisitionPoints.clear();
    _acquisitionTimer?.cancel();
    _confirmationTimer?.cancel();
    _currentStopId = null;
    _stateBeforeStop = null;
  }
  
  /// Вычисляет anchor как взвешенное среднее или медиану
  LocationFix? _calculateAnchor(List<LocationFix> points) {
    if (points.isEmpty) return null;
    
    // Фильтруем выбросы (точки, сильно отличающиеся от остальных)
    final filteredPoints = _filterOutliers(points);
    if (filteredPoints.isEmpty) return null;
    
    // Используем взвешенное среднее (вес = 1/accuracy²)
    double totalWeight = 0.0;
    double weightedLat = 0.0;
    double weightedLon = 0.0;
    double? avgAccuracy;
    double? avgSpeed;
    double? avgHeading;
    
    for (final point in filteredPoints) {
      final accuracy = point.accuracy ?? 50.0; // дефолт если нет точности
      final weight = 1.0 / (accuracy * accuracy);
      
      totalWeight += weight;
      weightedLat += point.latitude * weight;
      weightedLon += point.longitude * weight;
      
      if (point.accuracy != null) {
        avgAccuracy = (avgAccuracy ?? 0.0) + point.accuracy!;
      }
      if (point.speed != null) {
        avgSpeed = (avgSpeed ?? 0.0) + (point.speed ?? 0.0);
      }
      if (point.heading != null) {
        avgHeading = (avgHeading ?? 0.0) + (point.heading ?? 0.0);
      }
    }
    
    if (totalWeight == 0.0) return null;
    
    final lat = weightedLat / totalWeight;
    final lon = weightedLon / totalWeight;
    
    if (avgAccuracy != null) avgAccuracy /= filteredPoints.length;
    if (avgSpeed != null) avgSpeed /= filteredPoints.length;
    if (avgHeading != null) avgHeading /= filteredPoints.length;
    
    return LocationFix(
      latitude: lat,
      longitude: lon,
      accuracy: avgAccuracy,
      speed: avgSpeed,
      heading: avgHeading,
      provider: filteredPoints.first.provider,
      timestamp: filteredPoints.first.timestamp,
    );
  }
  
  /// Фильтрует выбросы (точки, далекие от медианы)
  List<LocationFix> _filterOutliers(List<LocationFix> points) {
    if (points.length <= 2) return points;
    
    // Вычисляем медиану
    final sortedLats = points.map((p) => p.latitude).toList()..sort();
    final sortedLons = points.map((p) => p.longitude).toList()..sort();
    
    final medianLat = sortedLats[sortedLats.length ~/ 2];
    final medianLon = sortedLons[sortedLons.length ~/ 2];
    
    final medianPoint = LocationFix(
      latitude: medianLat,
      longitude: medianLon,
      timestamp: points.first.timestamp,
    );
    
    // Вычисляем медианное расстояние
    final distances = points.map((p) => p.distanceTo(medianPoint)).toList()..sort();
    final medianDistance = distances[distances.length ~/ 2];
    
    // Фильтруем точки, которые слишком далеко от медианы
    final threshold = medianDistance * 2.0; // 2x медианное расстояние
    return points.where((p) => p.distanceTo(medianPoint) <= threshold).toList();
  }
  
  /// Вычисляет confidence на основе качества точек
  double _calculateConfidence(List<LocationFix> points) {
    if (points.isEmpty) return 0.0;
    
    double confidence = 0.5; // базовая уверенность
    
    // Бонус за количество точек
    final pointBonus = math.min(points.length / _maxPointsForAnchor, 0.3);
    confidence += pointBonus;
    
    // Бонус за хорошую точность
    final avgAccuracy = points
        .where((p) => p.accuracy != null)
        .map((p) => p.accuracy!)
        .fold(0.0, (a, b) => a + b) / points.length;
    
    if (avgAccuracy < 30.0) {
      confidence += 0.2; // отличная точность
    } else if (avgAccuracy < 50.0) {
      confidence += 0.1; // хорошая точность
    }
    
    return math.min(confidence, 1.0);
  }
  
  /// Получить текущий anchor (если есть)
  LocationFix? get currentAnchor => _stopAnchorCandidate;
  
  /// Проверяет, активна ли остановка
  bool get isStopActive => _currentStopId != null;
  
  void dispose() {
    _acquisitionTimer?.cancel();
    _confirmationTimer?.cancel();
    _stopConfirmedController.close();
    _stopEndedController.close();
  }
}

