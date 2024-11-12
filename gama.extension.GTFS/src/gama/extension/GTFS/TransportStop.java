package gama.extension.GTFS;

import gama.core.metamodel.shape.GamaPoint;

public class TransportStop {
    private String stopId;
    private String stopName;
    private GamaPoint location; // Utiliser GamaPoint pour gérer la localisation

    // Constructeur
    public TransportStop(String stopId, String stopName, double stopLat, double stopLon) {
        this.stopId = stopId;
        this.stopName = stopName;
        this.location = new GamaPoint(stopLat, stopLon);
    }
    
    public double getLatitude() {
        return location.getY();  // GamaPoint.getY() renvoie la latitude (y)
    }

    // Méthode pour obtenir la longitude (x)
    public double getLongitude() {
        return location.getX();  // GamaPoint.getX() renvoie la longitude (x)
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
}
