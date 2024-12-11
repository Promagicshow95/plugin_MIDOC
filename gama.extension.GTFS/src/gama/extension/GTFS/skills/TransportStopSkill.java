package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.setter;

import java.util.List;

import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.population.IPopulation;
import gama.core.runtime.IScope;
import gama.core.util.GamaListFactory;
import gama.core.util.GamaMapFactory;
import gama.core.util.IList;
import gama.core.util.IMap;
import gama.extension.GTFS.TransportStop;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;
import gama.gaml.types.Types;

/**
 * The skill TransportStopSkill for managing individual transport stops in GAMA.
 * This skill provides access to stopId, stopName, and structured departureInfoList for each stop.
 */
@skill(name = "TransportStopSkill", doc = @doc("Skill for agents representing individual transport stops. Provides access to stopId, stopName, and detailed departure information."))
@vars({
    @variable(name = "stopId", type = IType.STRING, doc = @doc("The ID of the transport stop.")),
    @variable(name = "stopName", type = IType.STRING, doc = @doc("The name of the transport stop.")),
    @variable(name = "departureInfoList", type = IType.LIST, doc = @doc("A list containing trips with departure times and their associated stops."))
})
public class TransportStopSkill extends Skill {

    // Getter and setter for stopId
    @getter("stopId")
    public String getStopId(final IAgent agent) {
        return (String) agent.getAttribute("stopId");
    }

    @setter("stopId")
    public void setStopId(final IAgent agent, final String stopId) {
        agent.setAttribute("stopId", stopId);
    }

    // Getter and setter for stopName
    @getter("stopName")
    public String getStopName(final IAgent agent) {
        return (String) agent.getAttribute("stopName");
    }

    @setter("stopName")
    public void setStopName(final IAgent agent, final String stopName) {
        agent.setAttribute("stopName", stopName);
    }

    // Getter for departureInfoList
    @getter("departureInfoList")
    @SuppressWarnings("unchecked")
    public IList<IList<Object>> getDepartureInfoList(final IAgent agent) {
        return (IList<IList<Object>>) agent.getAttribute("departureInfoList");
    }

    // Utility method: Retrieve all stop IDs and names for a given trip
    @getter("stopDetailsForTrip")
    public IList<IMap<String, String>> getStopDetailsForTrip(final IAgent agent, final int tripIndex) {
        IList<IList<Object>> departureInfoList = getDepartureInfoList(agent);
        if (departureInfoList == null || tripIndex >= departureInfoList.size()) {
            return null;
        }

        // Extraire les arrêts pour le trajet spécifié
        IList<Object> tripData = departureInfoList.get(tripIndex);
        @SuppressWarnings("unchecked")
        IList<IMap<String, Object>> stopsForTrip = (IList<IMap<String, Object>>) tripData.get(1);

        // Récupérer les détails des stops
        IList<IMap<String, String>> stopDetails = GamaListFactory.create();
        for (IMap<String, Object> stopEntry : stopsForTrip) {
            IMap<String, String> details = GamaMapFactory.create();
            details.put("stopId", (String) stopEntry.get("stopId"));
            details.put("departureTime", (String) stopEntry.get("departureTime"));
            stopDetails.add(details);
        }
        return stopDetails;
    }


    // Utility method: Retrieve the departure times of stops for a given trip
    @getter("departureTimesForTrip")
    @SuppressWarnings("unchecked")
    public IList<String> getDepartureTimesForTrip(final IAgent agent, final int tripIndex) {
        IList<IList<Object>> departureInfoList = getDepartureInfoList(agent);
        if (departureInfoList == null || tripIndex >= departureInfoList.size()) {
            return null;
        }

        // Extract the stops for the specified trip
        IList<Object> tripData = departureInfoList.get(tripIndex);
        IList<IMap<String, Object>> stopsForTrip = (IList<IMap<String, Object>>) tripData.get(1);

        // Extract the departure times
        IList<String> departureTimes = GamaListFactory.create();
        for (IMap<String, Object> stopEntry : stopsForTrip) {
            String departureTime = (String) stopEntry.get("departureTime");
            departureTimes.add(departureTime);
        }
        return departureTimes;
    }

    // Utility method: Retrieve the global departure time for a specific trip
    @getter("globalDepartureTimeForTrip")
    public String getGlobalDepartureTimeForTrip(final IAgent agent, final int tripIndex) {
        IList<IList<Object>> departureInfoList = getDepartureInfoList(agent);
        if (departureInfoList == null || tripIndex >= departureInfoList.size()) {
            return null;
        }

        // Extract the global departure time
        IList<Object> tripData = departureInfoList.get(tripIndex);
        return (String) tripData.get(0);
    }

    // Utility method: Retrieve the complete details of a trip
    @getter("tripDetails")
    @SuppressWarnings("unchecked")
    public IMap<String, Object> getTripDetails(final IAgent agent, final int tripIndex) {
        IList<IList<Object>> departureInfoList = getDepartureInfoList(agent);
        if (departureInfoList == null || tripIndex >= departureInfoList.size()) {
            return null;
        }

        IList<Object> tripData = departureInfoList.get(tripIndex);
        String globalDepartureTime = (String) tripData.get(0);
        @SuppressWarnings("unchecked")
        IList<IMap<String, Object>> stopsForTrip = (IList<IMap<String, Object>>) tripData.get(1);

        IMap<String, Object> tripDetails = GamaMapFactory.create();
        tripDetails.put("globalDepartureTime", globalDepartureTime);
        tripDetails.put("stops", stopsForTrip);

        return tripDetails;
    }

    
    /**
     * Extraire les stopId d'un trajet à partir de departureInfoList.
     * @param departureInfoList La liste des informations de départ (stopId et heures de départ).
     * @return Une liste des stopId associés au trajet.
     */
    public static IList<String> extractStopIdsFromTrip(IList<IList<Object>> departureInfoList) {
        IList<String> stopIds = GamaListFactory.create(Types.STRING);

        for (IList<Object> trip : departureInfoList) {
            if (trip.size() < 2) continue; // Chaque entrée doit contenir [tripDepartureTime, stopsForTrip]

            @SuppressWarnings("unchecked")
            IList<IMap<String, Object>> stopsForTrip = (IList<IMap<String, Object>>) trip.get(1);

            for (IMap<String, Object> stopEntry : stopsForTrip) {
                String stopId = (String) stopEntry.get("stopId");
                if (stopId != null) {
                    stopIds.add(stopId);
                }
            }
        }

        return stopIds;
    }


    /**
     * Récupérer les détails d'un arrêt à partir de son stopId.
     * @param scope Le contexte de simulation.
     * @param stopId L'identifiant unique de l'arrêt à rechercher.
     * @param population La population des agents TransportStop.
     * @return Les détails de l'arrêt correspondant ou null si non trouvé.
     */
    public static IAgent getStopDetailsFromPopulation(IScope scope, String stopId, IPopulation<? extends IAgent> population) {
        for (IAgent agent : population) {
            if (stopId.equals(agent.getAttribute("stopId"))) {
                // Log les détails de l'arrêt
                System.out.println("[Info] Stop trouvé : stopId = " + stopId + 
                                   ", stopName = " + agent.getAttribute("stopName") + 
                                   ", location = " + agent.getGeometry().getLocation());
                return agent;
            }
        }

        System.err.println("[Error] Aucun arrêt trouvé pour stopId = " + stopId);
        return null;
    }
}


           
