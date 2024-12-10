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

    // Nouvelle structure pour les informations de départ
    private IList<IList<Object>> departureInfoList;

    @SuppressWarnings("unchecked")
    public TransportStop(String stopId, String stopName, double stopLat, double stopLon, IScope scope) {
        this.stopId = stopId;
        this.stopName = stopName;
        this.location = SpatialUtils.toGamaCRS(scope, stopLat, stopLon);
        this.departureInfoList = GamaListFactory.create(Types.LIST); // Liste principale pour les trips
    }

    /**
     * Ajoute une information de départ pour un trajet.
     * 
     * @param departureTime Heure de départ globale pour le trip
     * @param stopsForTrip  Liste des arrêts associés au trajet avec leurs heures de départ
     */
    @SuppressWarnings("unchecked")
    public void addDepartureInfo(String departureTime, IList<IMap<String, Object>> stopsForTrip) {
        // Création de l'entrée principale pour ce trip
        IList<Object> tripEntry = GamaListFactory.create(Types.NO_TYPE);
        tripEntry.add(departureTime);  // Premier élément : heure de départ globale
        tripEntry.add(stopsForTrip);  // Deuxième élément : liste des arrêts avec leurs heures de départ

        // Ajout à la liste des informations de départ
        departureInfoList.add(tripEntry);
    }

    /**
     * Récupère les informations de départ pour ce stop.
     * 
     * @return Liste des informations de départ
     */
    public IList<IList<Object>> getDepartureInfoList() {
        return departureInfoList;
    }

    // Getters existants
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
        return "TransportStop{id='" + stopId + "', name='" + stopName + "', location=" + location + "}";
    }


    /**
     * Exemple de méthode utilitaire pour ajouter des arrêts avec leurs heures de départ
     * 
     * @param stop          Le stop à ajouter
     * @param departureTime L'heure de départ de ce stop
     * @return Une map représentant un arrêt avec son heure de départ
     */
    @SuppressWarnings("unchecked")
    public static IMap<String, Object> createStopEntry(TransportStop stop, String departureTime) {
    	 // Use GamaMapFactory for creating maps
        IMap<String, Object> stopEntry = GamaMapFactory.create(Types.STRING, Types.NO_TYPE);
        stopEntry.put("stop", stop);
        stopEntry.put("departureTime", departureTime);
        return stopEntry;
    }
}
