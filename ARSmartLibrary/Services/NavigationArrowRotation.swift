enum NavigationArrowRotation {
    static func angle(from current: Double, to bearing: Double) -> Double {
        let difference = (bearing - current).truncatingRemainder(dividingBy: 360)
        if difference > 180 { return current + difference - 360 }
        if difference < -180 { return current + difference + 360 }
        return current + difference
    }
}
