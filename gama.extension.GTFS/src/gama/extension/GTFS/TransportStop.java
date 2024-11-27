package gama.extension.GTFS;

import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.IShape;
import gama.gaml.operators.spatial.SpatialProjections;
import gama.core.runtime.IScope;

import java.util.HashSet;
import java.util.Set;

public class TransportStop {
    private String stopId; // ID de l'arrêt
    private String stopName; // Nom de l'arrêt
    private GamaPoint location; // Localisation transformée en GAMA CRS
    private Set<String> routePositions; // Rôles (START, END, etc.)

    // Constructeur
    public TransportStop(String stopId, String stopName, double stopLat, double stopLon, IScope scope) {
        this.stopId = stopId;
        this.stopName = stopName;
        this.location = convertToGamaCRS(scope, stopLat, stopLon);
        this.routePositions = new HashSet<>(); // Initialise les rôles comme un ensemble vide
    }

    /**
     * Méthode pour convertir latitude et longitude en GAMA CRS
     * @param scope - Le scope GAMA
     * @param lat - Latitude en EPSG:4326
     * @param lon - Longitude en EPSG:4326
     * @return GamaPoint en GAMA CRS
     */
    private GamaPoint convertToGamaCRS(IScope scope, double lat, double lon) {
        // Crée un GamaPoint pour la localisation originale
        GamaPoint rawLocation = new GamaPoint(lon, lat, 0.0); // Longitude (X), Latitude (Y), Altitude (Z)
        IShape transformedShape = SpatialProjections.to_GAMA_CRS(scope, rawLocation, "EPSG:4326");
        return (GamaPoint) transformedShape.getLocation();
    }

    // Getters
    public String getStopId() {
        return stopId;
    }

    public String getStopName() {
        return stopName;
    }

    public GamaPoint getLocation() {
        return location;
    }

    // Getter pour les rôles de l'arrêt
    public Set<String> getRoutePositions() {
        return routePositions != null ? routePositions : new HashSet<>();
    }

    // Ajoute un rôle au stop
    public void addRoutePosition(String position) {
        if (routePositions == null) {
            routePositions = new HashSet<>();
        }
        routePositions.add(position);
    }

    // Retourne une chaîne avec les rôles
    public String getRolesAsString() {
        return String.join(", ", routePositions);
    }

    // Get latitude depuis la localisation transformée
    public double getLatitude() {
        return location.getY();
    }

    // Get longitude depuis la localisation transformée
    public double getLongitude() {
        return location.getX();
    }

    // toString pour le débogage
    @Override
    public String toString() {
        return "Stop ID: " + stopId + ", Stop Name: " + stopName +
                ", Location: " + location.toString() +
                ", Roles: " + getRolesAsString();
    }
}
