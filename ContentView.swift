import SwiftUI
import CoreLocation

// MARK: - Palette (stessa dell'app Tripper Compass)

private enum FieldStyle {
    static let background = Color.black
    static let panel = Color(red: 0.09, green: 0.10, blue: 0.08)
    static let brass = Color(red: 0.79, green: 0.70, blue: 0.49)
    static let ivory = Color(red: 0.94, green: 0.90, blue: 0.77)
    static let muted = Color(red: 0.62, green: 0.63, blue: 0.56)
}

// MARK: - Temperatura

final class WeatherManager: NSObject,
                            ObservableObject,
                            CLLocationManagerDelegate {

    private let locationManager = CLLocationManager()
    private var lastFetch = Date.distantPast

    @Published var temperature: Double?
    @Published var place = ""
    @Published var status = "In attesa della posizione..."
    @Published var updated: Date?

    override init() {
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh(force: Bool = false) {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if !force && Date().timeIntervalSince(lastFetch) < 60 { return }
            lastFetch = Date()
            status = "Aggiornamento..."
            locationManager.requestLocation()

        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()

        case .denied, .restricted:
            status = "Posizione negata: abilitala in Impostazioni"

        @unknown default:
            status = "Posizione non disponibile"
        }
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        refresh(force: true)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            status = "Posizione non disponibile"
            return
        }

        CLGeocoder().reverseGeocodeLocation(location) { [weak self] marks, _ in
            DispatchQueue.main.async {
                self?.place = marks?.first?.locality ?? ""
            }
        }

        fetchTemperature(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        DispatchQueue.main.async {
            self.status = "Errore posizione"
        }
    }

    private func fetchTemperature(latitude: Double, longitude: Double) {
        var components = URLComponents(
            string: "https://api.open-meteo.com/v1/forecast"
        )

        components?.queryItems = [
            URLQueryItem(name: "latitude", value: "\(latitude)"),
            URLQueryItem(name: "longitude", value: "\(longitude)"),
            URLQueryItem(name: "current", value: "temperature_2m")
        ]

        guard let url = components?.url else {
            status = "URL meteo non valido"
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            guard error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let value = current["temperature_2m"] as? Double
            else {
                DispatchQueue.main.async {
                    self.status = "Meteo non disponibile"
                }
                return
            }

            DispatchQueue.main.async {
                self.temperature = value
                self.updated = Date()
                self.status = "TEMPERATURA ESTERNA"
            }
        }.resume()
    }
}

// MARK: - Interfaccia

struct ContentView: View {

    @StateObject private var weather = WeatherManager()
    @Environment(\.scenePhase) private var scenePhase

    private let timer = Timer.publish(every: 600, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        ZStack {
            FieldStyle.background.ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                Text("TEMPERATURA")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(FieldStyle.muted)

                if let temperature = weather.temperature {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", temperature))
                            .font(.system(size: 120, weight: .light, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(FieldStyle.ivory)

                        Text("°C")
                            .font(.system(size: 40, weight: .light, design: .monospaced))
                            .foregroundStyle(FieldStyle.brass)
                    }
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                } else {
                    Text("--°C")
                        .font(.system(size: 100, weight: .light, design: .monospaced))
                        .foregroundStyle(FieldStyle.muted)
                }

                if !weather.place.isEmpty {
                    Text(weather.place.uppercased())
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(FieldStyle.brass)
                }

                Text(weather.status)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(FieldStyle.muted)
                    .multilineTextAlignment(.center)

                if let updated = weather.updated {
                    Text("Aggiornato alle " + updated.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(FieldStyle.muted)
                }

                Spacer()

                Button {
                    weather.refresh(force: true)
                } label: {
                    Label("AGGIORNA", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(FieldStyle.brass)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(FieldStyle.brass.opacity(0.6), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
        .onAppear { weather.refresh() }
        .onReceive(timer) { _ in weather.refresh(force: true) }
        .onChange(of: scenePhase) { phase in
            if phase == .active { weather.refresh() }
        }
    }
}
