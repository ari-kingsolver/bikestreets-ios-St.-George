
import UIKit
import Mapbox

class MapViewController: UIViewController, MGLMapViewDelegate {

    @IBOutlet weak var mapView: MGLMapView!
    @IBOutlet weak var buttonWrapperView: UIView!
    @IBOutlet weak var debugInfoLabel: UILabel!
    
    // Array to hold on to observer objects for watching changes to UserDefaults
    var userSettingObservers: [NSObject]?
        
    struct MapStyles {
        // List of available styles here: https://docs.mapbox.com/api/maps/#styles
        static let street = URL(string: "mapbox://styles/mapbox/streets-v11")
        static let satellite = URL(string: "mapbox://styles/mapbox/satellite-v9")
        static let satelliteWithLabels = URL(string: "mapbox://styles/mapbox/satellite-streets-v9")
    }
    
    /**
     * Defaults for the map view
     */
    struct MapViewDefaults {
        static let mapStyle = MapStyles.street
        static let latitude = 39.7390
        static let longitude = -104.9911
        static let detailLevel = 14.0
    }
    
    // MARK: - UIViewController overrides
    override func viewDidLoad() {
        super.viewDidLoad()

        mapView.delegate = self
        
        // Initlize the map location with our default. We'll center it on the user later (assuming she gives us
        // permission)
        mapView.setCenter(CLLocationCoordinate2D(latitude: MapViewDefaults.latitude,
                                                 longitude: MapViewDefaults.longitude),
                          zoomLevel: MapViewDefaults.detailLevel,
                          animated: false)

        // Street or satellite view?
        configureMapStyle()
        configureMapPerspective()
        configureKeepScreenOn()

        // Style the buttons
        buttonWrapperView.layer.cornerRadius = 5.0
        buttonWrapperView.layer.masksToBounds = true
     
        configureUserSettingObservers()
        
        #if DEBUG
        debugInfoLabel.isHidden = false
        #else
        debugInfoLabel.isHidden = true
        #endif
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }

    // MARK: - MGLMapViewDelegate
    
    func mapView(_ mapView: MGLMapView, didFinishLoading style: MGLStyle) {
        // Wait until the map is loaded before adding to the map.
        loadMapFromShippedResources()
    }
    
    #if DEBUG
    func mapViewRegionIsChanging(_ mapView: MGLMapView) {
        debugInfoLabel.text = "Zoom Level: \(mapView.zoomLevel.rounded())"
    }
    #endif
    
    // MARK: - Load Bike Streets Data
    
    /**
     * Load the default Bike Streets map from KML resources files bundled into the app
     */
    func loadMapFromShippedResources() {
        // TODO: Versioning scheme for the geojson data
        // TODO: Do we have a cached/downloaded version of the geojson data?
        // TODO: Is our cached version of geojson the latest & greatest?

        DispatchQueue.global().async {
            if let fileURLs = Bundle.main.urls(forResourcesWithExtension: "geojson", subdirectory: nil) {
                for fileURL in fileURLs {
                    self.loadMapLayerFrom(fileURL)
                }
            }
        }
    }
 
    func loadMapLayerFrom(_ fileURL: URL) {
        let layerName = fileURL.lastPathComponent.layerName()
        

        guard let jsonData = try? Data(contentsOf: fileURL) else {
            preconditionFailure("Failed to parse GeoJSON file")
        }
        
        guard let shapeFromGeoJSON = try? MGLShape(data: jsonData, encoding: String.Encoding.utf8.rawValue) else {
            fatalError("Could not generate MGLShape")
        }
        
        let source = MGLShapeSource(identifier: layerName, shape: shapeFromGeoJSON, options: nil)
        let layer: MGLStyleLayer!
        
        switch layerName {
        case "bikestreets":
            layer = BikeStreetsStyles.bikeStreetStyleLayer(withIdentifier: layerName, source: source)
        case "trails":
            layer = BikeStreetsStyles.trailStyleLayer(withIdentifier: layerName, source: source)
        case "bikelanes":
            layer = BikeStreetsStyles.bikeLaneStyleLayer(withIdentifier: layerName, source: source)
        case "bikesidewalks":
            layer = BikeStreetsStyles.bikeStreetStyleLayer(withIdentifier: layerName, source: source)
        case "walk":
            layer = BikeStreetsStyles.walkStyleLayer(withIdentifier: layerName, source: source)
        default:
            fatalError("ack")
        }

        DispatchQueue.main.async {
            // Add our GeoJSON data to the map as an MGLGeoJSONSource.
            // We can then reference this data from an MGLStyleLayer.
        
            // MGLMapView.style is optional, so you must guard against it not being set.
            guard let style = self.mapView.style else { return }
        
            style.addSource(source)
            style.addLayer(layer)
        }
    }
    
    // MARK: - Configuration Methods
    
    /**
     * Street or Satellite view?
     */
    func configureMapStyle() {
        if UserSettings.mapViewType == MapViewType.satellite.rawValue {
            mapView.styleURL = MapStyles.satelliteWithLabels
        } else {
            mapView.styleURL = MapStyles.street
        }
    }
    
    /**
     * Change the map's perspective depending upon the user setting
     */
    func configureMapPerspective(isChange: Bool = false) {
        mapView.showsUserLocation = true
        
        // How should we orient the map? North or Direction of Travel?
        if (UserSettings.mapOrientation == MapDirectionOfTravel.directionOfTravel.rawValue) {
            mapView.userTrackingMode = .followWithHeading
            mapView.showsUserHeadingIndicator = true
        } else {
            mapView.userTrackingMode = .follow
            mapView.showsUserHeadingIndicator = false

            if isChange {
                // We should not change the viewpoint rotation & (re)center the map unless this is a change
                // in map perspective.
                centerMapOnCurrentLocation()
            }
        }
    }
    
    /**
     * Do we need to prevent the screen from locking?
     */
    func configureKeepScreenOn() {
        UIApplication.shared.isIdleTimerDisabled = UserSettings.preventScreenLockOnMap
    }
    
    /**
     * Recenter the map on the current location, but don't change the zoom level
     */
    func centerMapOnCurrentLocation() {
        guard let userLocation = mapView.userLocation else {
            return
        }
        
        if !mapView.isUserLocationVisible {
            mapView.setCenter(userLocation.coordinate, animated: true)
        }
    }
    
    /**
     * Watch for changes to the UserSettings
     */
    func configureUserSettingObservers() {
        var observer = UserSettings.$mapViewType.observe { [weak self] old, new in
            guard let strongSelf = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5,
                                          execute: {
                                            strongSelf.configureMapStyle()
            })
        }
        userSettingObservers?.append(observer)
        observer = UserSettings.$mapOrientation.observe { [weak self] old, new in
            guard let strongSelf = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5,
                                          execute: {
                                            strongSelf.configureMapPerspective(isChange: true)
            })
        }
        userSettingObservers?.append(observer)
        observer = UserSettings.$preventScreenLockOnMap.observe { [weak self] old, new in
            guard let strongSelf = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5,
                                          execute: {
                                            strongSelf.configureKeepScreenOn()
            })
        }
        userSettingObservers?.append(observer)
    }
    
    // MARK: - Button Action Methods
    
    @IBAction func infoButtonTapped(_ sender: Any) {
        let mapSettingsViewController = MapSettingsViewController()
        let navController = UINavigationController(rootViewController: mapSettingsViewController)
        present(navController, animated: true, completion: nil)
    }
    
    @IBAction func locationButtonTapped(_ sender: Any) {
        centerMapOnCurrentLocation()
    }
}

private extension String {
    func layerName() -> String {
        let fileNameComponents = components(separatedBy: "-")
        return fileNameComponents[1]
    }
}

struct BikeStreetsStyles {
    static let bikeStreetBlue = UIColor(red: 0/255, green: 0/255, blue: 255/255, alpha: 0.7)
    static let trailGreen = UIColor(red: 0/255, green: 178/255, blue: 0/255, alpha: 0.7)
    static let bikeLaneOrange = UIColor(red: 216/255, green: 146/255, blue: 15/255, alpha: 0.7)
    static let walkBlack = UIColor(red: 0/255, green: 0/255, blue: 0/255, alpha: 0.7)

    // Use `NSExpression` to smoothly adjust the line width from 2pt to 20pt between zoom levels 14 and 18. The `interpolationBase` parameter allows the values to interpolate along an exponential curve.
    static let lineWidth =  NSExpression(format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)",
          [14: 2, 18: 8])
    
    static func bikeStreetStyleLayer(withIdentifier identifier: String, source: MGLShapeSource) -> MGLStyleLayer {
        // Create new layer for the line.
        let layer = MGLLineStyleLayer(identifier: identifier, source: source)
    
        // Set the line join and cap to a rounded end.
        layer.lineJoin = NSExpression(forConstantValue: "round")
        layer.lineCap = NSExpression(forConstantValue: "round")
    
        layer.lineColor = NSExpression(forConstantValue: bikeStreetBlue)
        layer.lineWidth = lineWidth
                
        return layer
    }
    static func trailStyleLayer(withIdentifier identifier: String, source: MGLShapeSource) -> MGLStyleLayer {
       // Create new layer for the line.
       let layer = MGLLineStyleLayer(identifier: identifier, source: source)
    
       // Set the line join and cap to a rounded end.
       layer.lineJoin = NSExpression(forConstantValue: "round")
       layer.lineCap = NSExpression(forConstantValue: "round")
    
       layer.lineColor = NSExpression(forConstantValue: trailGreen)
       layer.lineWidth = lineWidth
                
        return layer
    }
    static func bikeLaneStyleLayer(withIdentifier identifier: String, source: MGLShapeSource) -> MGLStyleLayer {
       // Create new layer for the line.
       let layer = MGLLineStyleLayer(identifier: identifier, source: source)
    
       // Set the line join and cap to a rounded end.
       layer.lineJoin = NSExpression(forConstantValue: "round")
       layer.lineCap = NSExpression(forConstantValue: "round")
    
       layer.lineColor = NSExpression(forConstantValue: bikeLaneOrange)
       layer.lineWidth = lineWidth
                
        return layer
    }
    static func walkStyleLayer(withIdentifier identifier: String, source: MGLShapeSource) -> MGLStyleLayer {
       // Create new layer for the line.
       let layer = MGLLineStyleLayer(identifier: identifier, source: source)
    
       // Set the line join and cap to a rounded end.
       layer.lineJoin = NSExpression(forConstantValue: "round")
       layer.lineCap = NSExpression(forConstantValue: "round")
    
       layer.lineColor = NSExpression(forConstantValue: walkBlack)
       layer.lineWidth = lineWidth
                
        return layer
    }
}
