package gama.extension.GTFS;

import gama.core.metamodel.shape.GamaPoint;
import gama.core.runtime.IScope;
import gama.core.util.GamaListFactory;
import gama.core.util.GamaMapFactory;
import gama.core.util.IList;
import gama.core.util.IMap;
import gama.gaml.types.Types;
import GamaGTFSUtils.SpatialUtils;

public class TransportStop {
    private String stopId;
    private String stopName;
    private GamaPoint location;
    private IList<IList<Object>> departureInfoList;

    @SuppressWarnings("unchecked")
    public TransportStop(String stopId, String stopName, double stopLat, double stopLon, IScope scope) {
        this.stopId = stopId;
        this.stopName = stopName;
        this.location = SpatialUtils.toGamaCRS(scope, stopLat, stopLon);
        this.departureInfoList = GamaListFactory.create(Types.LIST); // Initialise la liste des trips
    }

    /**
     * Ajoute une information de départ pour un trajet.
     * 
     * @param departureTime Heure de départ globale pour le trip
     * @param stopsForTrip  Liste des arrêts associés au trajet
     */
    public void addDepartureInfo(String departureTime, IList<IMap<String, Object>> stopsForTrip) {
        IList<Object> tripEntry = GamaListFactory.create();
        tripEntry.add(departureTime);
        tripEntry.add(stopsForTrip);
        departureInfoList.add(tripEntry);
    }

    /**
     * Vérifie si la liste des départs est vide.
     */
    public boolean hasDepartureInfo() {
        return departureInfoList != null && !departureInfoList.isEmpty();
    }

    public IList<IList<Object>> getDepartureInfoList() {
        return departureInfoList;
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
        return "TransportStop{id='" + stopId + "', name='" + stopName + "', location=" + location + ", departureInfo=" + departureInfoList + "}";
    }

    public static IMap<String, Object> createStopEntry(String stopId, String departureTime) {
        IMap<String, Object> stopEntry = GamaMapFactory.create(Types.STRING, Types.NO_TYPE);
        stopEntry.put("stopId", stopId);
        stopEntry.put("departureTime", departureTime);
        return stopEntry;
    }
}
