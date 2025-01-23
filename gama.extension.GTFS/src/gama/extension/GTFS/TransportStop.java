package gama.extension.GTFS;

import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.shape.GamaPoint;
import gama.core.runtime.IScope;
import gama.core.util.GamaListFactory;
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
    private IMap<String, IMap<String, Object>> departureTripsInfo; 

    @SuppressWarnings("unchecked")
    public TransportStop(String stopId, String stopName, double stopLat, double stopLon, IScope scope) {
        this.stopId = stopId;
        this.stopName = stopName;
        this.location = SpatialUtils.toGamaCRS(scope, stopLat, stopLon);
        this.departureTripsInfo = GamaMapFactory.create(Types.STRING, Types.MAP);
    }

    public String getStopId() {
        return stopId;
    }

    public String getStopName() {
        return stopName;
    }

    public GamaPoint getLocation() {
        return location;
    }

    public IMap<String, IMap<String, Object>> getDepartureTripsInfo() {
        return departureTripsInfo;
    }

    /**
     * Add ordered stops to the departureTripsInfo structure.
     * 
     * @param tripId       Trip ID for which stops are being added.
     * @param orderedStops List of stop IDs and departure times.
     */
    @SuppressWarnings("unchecked")
    public void addOrderedStops(String tripId, IList<IMap<String, String>> orderedStops) {
        if (departureTripsInfo.get(tripId) == null) {
            IMap<String, Object> tripInfo = GamaMapFactory.create();
            tripInfo.put("orderedStops", orderedStops);
            tripInfo.put("convertedStops", GamaListFactory.create(Types.PAIR));
            departureTripsInfo.put(tripId, tripInfo);
        } else {
            IMap<String, Object> tripInfo = departureTripsInfo.get(tripId);
            tripInfo.put("orderedStops", orderedStops);
        }
    }

    /**
     * Add converted stops to the departureTripsInfo structure.
     * 
     * @param tripId         Trip ID for which stops are being added.
     * @param convertedStops List of GamaPair of agent stops and their departure times.
     */
    @SuppressWarnings("unchecked")
    public void addConvertedStops(String tripId, IList<GamaPair<IAgent, String>> convertedStops) {
        if (departureTripsInfo.get(tripId) == null) {
            IMap<String, Object> tripInfo = GamaMapFactory.create();
            tripInfo.put("orderedStops", GamaListFactory.create(Types.MAP));
            tripInfo.put("convertedStops", convertedStops);
            departureTripsInfo.put(tripId, tripInfo);
        } else {
            IMap<String, Object> tripInfo = departureTripsInfo.get(tripId);
            tripInfo.put("convertedStops", convertedStops);
        }
    }

    @Override
    public String toString() {
        String locationStr = (location != null) 
                ? String.format("x=%.2f, y=%.2f", location.getX(), location.getY()) 
                : "null";
        return "TransportStop{id='" + stopId + "', name='" + stopName 
               + "', location={" + locationStr + "}, "
               + "departureTripsInfo=" + departureTripsInfo + "}";
    }

    /**
     * Adds a trip's information to the departureTripsInfo map.
     * 
     * @param tripId The unique identifier for the trip.
     * @param tripInfo The trip information to be added.
     */
    public void addDepartureTripInfo(String tripId, IMap<String, Object> tripInfo) {
        if (tripId != null && tripInfo != null) {
            departureTripsInfo.put(tripId, tripInfo);
        } else {
            System.err.println("[ERROR] tripId or tripInfo is null in addDepartureTripInfo.");
        }
    }
}
