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
    private IMap<String, IList<GamaPair<String, String>>> departureTripsInfo;

    @SuppressWarnings("unchecked")
    public TransportStop(String stopId, String stopName, double stopLat, double stopLon, IScope scope) {
        this.stopId = stopId;
        this.stopName = stopName;
        this.location = SpatialUtils.toGamaCRS(scope, stopLat, stopLon);
        this.departureTripsInfo = null;  
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

    public IMap<String, IList<GamaPair<String, String>>> getDepartureTripsInfo() {
        return departureTripsInfo;
    }

    /**
     * Add stops information as list of GamaPairs to the departureTripsInfo structure.
     *
     * @param tripId       Trip ID for which stops are being added.
     * @param stopPairs    List of GamaPair containing stop IDs and departure times.
     */
    @SuppressWarnings("unchecked")
    public void addStopPairs(String tripId, IList<GamaPair<String, String>> stopPairs) {
        departureTripsInfo.put(tripId, stopPairs);
    }

    public void ensureDepartureTripsInfo() {
        if (this.departureTripsInfo == null) {
            this.departureTripsInfo = GamaMapFactory.create(Types.STRING, Types.LIST);
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
}
