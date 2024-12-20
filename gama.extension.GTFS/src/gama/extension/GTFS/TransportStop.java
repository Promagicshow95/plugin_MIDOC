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
    private IMap<String, IAgent> departureInfoMap; // Updated to Map<Time, IAgent>
    private IList<String> orderedStopIds; // New field to store ordered stop IDs

    @SuppressWarnings("unchecked")
    public TransportStop(String stopId, String stopName, double stopLat, double stopLon, IScope scope) {
        this.stopId = stopId;
        this.stopName = stopName;
        this.location = SpatialUtils.toGamaCRS(scope, stopLat, stopLon);
        this.departureInfoMap = GamaMapFactory.create(Types.STRING, Types.AGENT);
        this.orderedStopIds = GamaListFactory.create(Types.STRING);
        
        
    }
    /**
     * Adds departure information for a trip.
     *
     * @param departureTime Global departure time for the trip.
     * @param stop          The corresponding TransportStop object.
     */
    public void addDepartureInfo(String departureTime, IAgent stop) {
        if (departureTime != null && stop != null) {
            departureInfoMap.put(departureTime, stop);
        } else {
            System.err.println("[ERROR] departureTime or stop is null in addDepartureInfo.");
        }
    }


    public IMap<String, IAgent> getDepartureInfoMap() {
        return departureInfoMap;
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
    
    // Add a stop ID to the ordered list
    public void addOrderedStopId(String stopId) {
        if (stopId != null && !stopId.isEmpty()) {
            orderedStopIds.add(stopId);
        }
    }
    
 // Getter for the ordered stop IDs
    public IList<String> getOrderedStopIds() {
        return orderedStopIds;
    }

    @Override
    public String toString() {
        String locationStr = (location != null) ? 
                             String.format("x=%.2f, y=%.2f", location.getX(), location.getY()) : "null";
        return "TransportStop{id='" + stopId + 
               "', name='" + stopName + 
               "', location={" + locationStr + "}, " +  "', listId={" + orderedStopIds + "}, " +
               "departureInfoMap=" + (departureInfoMap != null ? departureInfoMap.size() + " entries" : "null") + "}";
    }


}
