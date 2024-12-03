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

    // Nouvelle structure pour les associations de trajets
    private IMap<Integer, IList<TransportStop>> tripAssociations;

    // Nouvelle structure pour les destinations
    private IMap<Integer, String> destinationMap;

    @SuppressWarnings("unchecked")
    public TransportStop(String stopId, String stopName, double stopLat, double stopLon, IScope scope) {
        this.stopId = stopId;
        this.stopName = stopName;
        this.location = SpatialUtils.toGamaCRS(scope, stopLat, stopLon);
        this.tripAssociations = GamaMapFactory.create(Types.INT, Types.get(IList.class));
        this.destinationMap = GamaMapFactory.create(Types.INT, Types.STRING); // Map for the destination
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
     * Définit la destination pour un tripId donné.
     * @param tripId ID du trajet
     * @param destination Id de l'arrêt de destination
     */
    public void setDestination(int tripId, String destination) {
        destinationMap.put(tripId, destination);
    }

    /**
     * Récupère la destination pour un tripId donné.
     * @param tripId ID du trajet
     * @return Id de l'arrêt de destination ou null si non défini
     */
    public String getDestination(int tripId) {
        String destination = destinationMap.get(tripId);
        System.out.println("[Debug] Fetching destination for tripId=" + tripId + ": " + destination);
        return destination;
    }

 
    /**
     * Récupère toutes les associations des trips avec leurs prédécesseurs.
     * @return Map des associations
     */
    public IMap<Integer, IList<TransportStop>> getTripAssociations() {
        return tripAssociations;
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
    
    /**
     * Adds or updates the destination for a specific tripId.
     * @param tripId ID of the trip.
     * @param destination The destination stopId.
     */
    public void addDestination(Integer tripId, String destination) {
        destinationMap.put(tripId, destination);
    }

    public IMap<Integer, String> getDestinationMap() {
        System.out.println("[Debug] Fetching destination map: " + destinationMap);
        return destinationMap;
    }
    @Override
    public String toString() {
        return "Stop ID: " + stopId + ", Stop Name: " + stopName +
                ", Location: " + location.toString();
    }
}
