/// Состояния движения пользователя
enum ActivityState {
  /// Пользователь стоит
  still,
  
  /// Пользователь идет (включая бег)
  walking,
  
  /// Пользователь в транспорте (автомобиль, автобус, поезд)
  inVehicle,
}

extension ActivityStateExtension on ActivityState {
  String get name {
    switch (this) {
      case ActivityState.still:
        return 'STILL';
      case ActivityState.walking:
        return 'WALKING';
      case ActivityState.inVehicle:
        return 'IN_VEHICLE';
    }
  }
  
  static ActivityState? fromString(String value) {
    switch (value.toUpperCase()) {
      case 'STILL':
        return ActivityState.still;
      case 'WALKING':
        return ActivityState.walking;
      case 'IN_VEHICLE':
        return ActivityState.inVehicle;
      default:
        return null;
    }
  }
}

