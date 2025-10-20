package gama.extension.GTFS;

import gama.core.metamodel.shape.GamaPoint;
import gama.core.runtime.IScope;
import gama.core.util.GamaMapFactory;
import gama.core.util.GamaPair;
import gama.core.util.IList;
import gama.core.util.IMap;

import GamaGTFSUtils.SpatialUtils;
import gama.gaml.types.Types;

public class TransportStop {

    private String stopId;
    private String stopName;
    private double stopLat;   // Latitude originale du GTFS
    private double stopLon;   // Longitude originale du GTFS
    private GamaPoint location;
    private int routeType = -1;
    private int tripNumber = 0; 
    private IMap<String, IList<GamaPair<String, String>>> departureTripsInfo;
    private IMap<String, String> tripShapeMap;
    private IMap<String, IList<Double>> departureShapeDistances;

    @SuppressWarnings("unchecked")
    public TransportStop(String stopId, String stopName, double stopLat, double stopLon, IScope scope) {
        this.stopId = stopId;
        this.stopName = stopName;
        this.stopLat = stopLat;
        this.stopLon = stopLon;
        // Conversion pour la simulation GAMA (en CRS interne)
        this.location = SpatialUtils.toGamaCRS(scope, stopLat, stopLon);
        this.departureTripsInfo = null;
        this.tripShapeMap = GamaMapFactory.create(Types.STRING, Types.STRING);
        this.departureShapeDistances = GamaMapFactory.create(Types.STRING, Types.LIST);
        //System.out.println("[TEST] Coordonnées projetées pour " + stopName + ": " + location);
    }

    // --- ACCESSEURS classiques
    public String getStopId() { return stopId; }
    public String getStopName() { return stopName; }
    public GamaPoint getLocation() { return location; }
    public int getRouteType() { return routeType; }
    public void setRouteType(int routeType) { this.routeType = routeType; }

  
    public double getStopLat() { return stopLat; }
    public double getStopLon() { return stopLon; }

    public IMap<String, IList<GamaPair<String, String>>> getDepartureTripsInfo() { return departureTripsInfo; }

    public void addStopPairs(String tripId, IList<GamaPair<String, String>> stopPairs) {
        departureTripsInfo.put(tripId, stopPairs);
    }

    public void setDepartureTripsInfo(IMap<String, IList<GamaPair<String, String>>> departureTripsInfo) {
        this.departureTripsInfo = departureTripsInfo;
    }

    @SuppressWarnings("unchecked")
    public void ensureDepartureTripsInfo() {
        if (this.departureTripsInfo == null) {
            this.departureTripsInfo = GamaMapFactory.create(Types.STRING, Types.LIST);
        }
    }

    public IMap<String, String> getTripShapeMap() { return tripShapeMap; }

    public void addTripShapePair(String tripId, String shapeId) { this.tripShapeMap.put(tripId, shapeId); }
    
    public IMap<String, IList<Double>> getDepartureShapeDistances() {
        return departureShapeDistances;
    }

    public void addDepartureShapeDistances(String tripId, IList<Double> distances) {
        departureShapeDistances.put(tripId, distances);
    }
    
    public int getTripNumber() {
        return tripNumber;
    }
    
    public void setTripNumber(int tripNumber) {
        this.tripNumber = tripNumber;
    }

    @Override
    public String toString() {
        String locationStr = (location != null)
                ? String.format("x=%.2f, y=%.2f", location.getX(), location.getY())
                : "null";
        return "TransportStop{id='" + stopId + "', name='" + stopName
                + "', location={" + locationStr + "}, "
                + "routeType=" + routeType + ", "
                + "tripShapeMap=" + tripShapeMap + "}";
    }

    public GamaPoint getGeometry() {
        return location;
    }
}
