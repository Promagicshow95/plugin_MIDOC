package gama.extension.GTFS;

import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.shape.GamaPoint;
import gama.core.runtime.IScope;
import gama.core.util.GamaListFactory;
import gama.core.util.GamaMapFactory;
import gama.core.util.IList;
import gama.core.util.IMap;
import GamaGTFSUtils.SpatialUtils;

import gama.gaml.types.Types;

public class TransportStop {
    private String stopId;
    private String stopName;
    private GamaPoint location;

    // Stores trip information: Map<tripId, tripDetails>
    private IMap<String, IMap<String, Object>> departureTripsInfo;

    @SuppressWarnings("unchecked")
    public TransportStop(String stopId, String stopName, double stopLat, double stopLon, IScope scope) {
        this.stopId = stopId;
        this.stopName = stopName;
        this.location = SpatialUtils.toGamaCRS(scope, stopLat, stopLon);
        this.departureTripsInfo = GamaMapFactory.create(Types.STRING, Types.MAP);
    }

    /**
     * Adds trip information to departureTripsInfo.
     *
     * @param tripId          The trip identifier.
     * @param departureTime   The departure time for this trip from this stop.
     * @param orderedStops    Ordered stops for this trip, as Map<stopId, departureTime>.
     * @param convertedStops  Ordered agents (IAgent) for this trip.
     */
    @SuppressWarnings("unchecked")
	public void addTripInfo(String tripId, String departureTime, IList<IMap<String, String>> orderedStops, IList<IAgent> convertedStops) {
        if (tripId != null && departureTime != null && orderedStops != null && convertedStops != null) {
            IMap<String, Object> tripDetails = GamaMapFactory.create(Types.STRING, Types.NO_TYPE);
            tripDetails.put("departureTime", departureTime);
            tripDetails.put("orderedStops", orderedStops);
            tripDetails.put("convertedStops", convertedStops);
            departureTripsInfo.put(tripId, tripDetails);
        } else {
            System.err.println("[ERROR] Invalid data provided to addTripInfo for stopId=" + stopId);
        }
    }

    /**
     * Getter for departureTripsInfo.
     *
     * @return The map of trip information for this stop.
     */
    public IMap<String, IMap<String, Object>> getDepartureTripsInfo() {
        return departureTripsInfo;
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

    @Override
    public String toString() {
        String locationStr = (location != null)
            ? String.format("x=%.2f, y=%.2f", location.getX(), location.getY())
            : "null";

        return "TransportStop{id='" + stopId +
               "', name='" + stopName +
               "', location={" + locationStr + "}, " +
               "departureTripsInfo=" + (departureTripsInfo != null ? departureTripsInfo.size() + " entries" : "null") + "}";
    }

    /**
     * Adds a trip's information to the departureTripsInfo map.
     *
     * @param tripId The ID of the trip.
     * @param tripInfo The trip information map containing orderedStops and other details.
     */
    public void addDepartureTripInfo(String tripId, IMap<String, Object> tripInfo) {
        if (tripId != null && tripInfo != null) {
            departureTripsInfo.put(tripId, tripInfo);
        } else {
            System.err.println("[ERROR] tripId or tripInfo is null in addDepartureTripInfo.");
        }
    }
}
