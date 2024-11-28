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
    
    private IMap<Integer, IList<TransportStop>> tripAssociations; // Map de tripId -> Liste des prédécesseurs
    private IMap<Integer, String> tripHeadsigns; // Map of tripId -> headsign

    @SuppressWarnings("unchecked")
    public TransportStop(String stopId, String stopName, double stopLat, double stopLon, IScope scope) {
        this.stopId = stopId;
        this.stopName = stopName;
        this.location = SpatialUtils.toGamaCRS(scope, stopLat, stopLon);
        this.tripAssociations = GamaMapFactory.create(Types.INT, Types.get(IList.class)); // Map avec des listes de prédécesseurs
        this.tripHeadsigns = GamaMapFactory.create(Types.INT, Types.STRING);
    }

    /**
     * Ajoute ou met à jour les prédécesseurs pour un tripId donné.
     * @param tripId ID du trajet
     * @param predecessors Liste des arrêts prédécesseurs
     */
    public void addTripWithPredecessors(int tripId, IList<TransportStop> predecessors) {
        tripAssociations.put(tripId, predecessors);
    }

    /**
     * Récupère les prédécesseurs d'un arrêt pour un tripId donné.
     * @param tripId ID du trajet
     * @return Liste des prédécesseurs, ou une liste vide si non défini
     */
    public IList<TransportStop> getPredecessors(int tripId) {
        return tripAssociations.getOrDefault(tripId, GamaListFactory.create());
    }

    /**
     * Ajoute un headsign pour un tripId donné.
     * @param tripId ID du trajet
     * @param headsign Le headsign associé
     */
    public void addHeadsign(int tripId, String headsign) {
        tripHeadsigns.put(tripId, headsign);
    }

    /**
     * Récupère le headsign pour un tripId donné.
     * @return Le headsign ou null si non défini
     */
    public String getHeadsign(int tripId) {
        return tripHeadsigns.get(tripId);
    }

    /**
     * Récupère toutes les associations des trips avec leurs prédécesseurs.
     * @return Map des associations
     */
    public IMap<Integer, IList<TransportStop>> getTripAssociations() {
        return tripAssociations;
    }

    /**
     * Récupère toutes les headsigns des trips.
     * @return Map des headsigns
     */
    public IMap<Integer, String> getTripHeadsigns() {
        return tripHeadsigns;
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

    // Get latitude depuis la localisation transformée
    public double getLatitude() {
        return location.getY();
    }

    // Get longitude depuis la localisation transformée
    public double getLongitude() {
        return location.getX();
    }

    // toString pour le débogage
    @Override
    public String toString() {
        return "Stop ID: " + stopId + ", Stop Name: " + stopName +
                ", Location: " + location.toString();
    }
}
