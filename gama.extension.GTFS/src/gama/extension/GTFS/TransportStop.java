package gama.extension.GTFS;

import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.IShape;
import gama.gaml.operators.spatial.SpatialProjections;
import gama.core.runtime.IScope;

public class TransportStop {
    private String stopId;
    private String stopName;
    private GamaPoint location; // Using GamaPoint to store the transformed location

    // Constructor
    public TransportStop(String stopId, String stopName, double stopLat, double stopLon, IScope scope) {
        this.stopId = stopId;
        this.stopName = stopName;
        
        // Convert raw coordinates to GAMA CRS using the GAMA operator "to_GAMA_CRS"
        this.location = convertToGamaCRS(scope, stopLat, stopLon);
    }

    /**
     * Method to convert latitude and longitude to GAMA CRS
     * @param scope - The GAMA scope
     * @param lat - Latitude in EPSG:4326
     * @param lon - Longitude in EPSG:4326
     * @return GamaPoint in the GAMA CRS
     */
    private GamaPoint convertToGamaCRS(IScope scope, double lat, double lon) {
        // Create a GamaPoint for the original location
        GamaPoint rawLocation = new GamaPoint(lon, lat, 0.0); // Longitude (X), Latitude (Y), Altitude (Z)
        System.out.println("Raw location: " + rawLocation);
        // Transform the point to the GAMA CRS using the operator "to_GAMA_CRS"
        IShape transformedShape = SpatialProjections.to_GAMA_CRS(scope, rawLocation, "EPSG:4326");
        
        System.out.println("Transformed location: " + transformedShape.getLocation());
        
     System.out.println("Transformed location: " + transformedShape.getLocation());


        // Return the location as a GamaPoint
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

    // Get latitude from the transformed location
    public double getLatitude() {
        return location.getY();
    }

    // Get longitude from the transformed location
    public double getLongitude() {
        return location.getX();
    }

    // toString for debugging
    @Override
    public String toString() {
        return "Stop ID: " + stopId + ", Stop Name: " + stopName + ", Location: " + location.toString();
    }
}
