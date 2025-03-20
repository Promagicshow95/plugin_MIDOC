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
    private GamaPoint location;
    private int routeType = -1;
    private IMap<String, IList<GamaPair<String, String>>> departureTripsInfo;
    private IMap<String, Integer> tripShapeMap;

    @SuppressWarnings("unchecked")
	public TransportStop(String stopId, String stopName, double stopLat, double stopLon, IScope scope) {
        this.stopId = stopId;
        this.stopName = stopName;
        this.location = SpatialUtils.toGamaCRS(scope, stopLat, stopLon);
        this.departureTripsInfo = null;
        this.tripShapeMap = GamaMapFactory.create(Types.STRING, Types.INT);
    }

    public String getStopId() { return stopId; }
    public String getStopName() { return stopName; }
    public GamaPoint getLocation() { return location; }
    public int getRouteType() { return routeType; }
    public void setRouteType(int routeType) { this.routeType = routeType; }

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


    public IMap<String, Integer> getTripShapeMap() {
        return tripShapeMap;
    }

   
    public void addTripShapePair(String tripId, int shapeId) {
        this.tripShapeMap.put(tripId, shapeId);
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
}
