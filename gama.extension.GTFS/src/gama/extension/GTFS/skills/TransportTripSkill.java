package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.setter;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.gaml.skills.Skill;
import gama.core.metamodel.agent.IAgent;
import gama.gaml.types.IType;

/**
 * The skill TransportTripSkill for managing individual transport trips in GAMA.
 * This skill manages attributes like tripId, routeId, stopsInOrder, destination, and stopDetails.
 */
@skill(name = "TransportTripSkill", doc = @doc("Skill for agents that represent individual transport trips with attributes like tripId, routeId, stopsInOrder, destination, and stopDetails."))
@vars({
    @variable(name = "tripId", type = IType.INT, doc = @doc("The unique identifier of the transport trip.")),
    @variable(name = "routeId", type = IType.STRING, doc = @doc("The unique identifier of the route associated with the trip.")),
    @variable(name = "stopsInOrder", type = IType.LIST, doc = @doc("The ordered list of stop IDs for this trip.")),
    @variable(name = "destination", type = IType.STRING, doc = @doc("The final stop ID for this trip.")),
    @variable(name = "stopDetails", type = IType.LIST, doc = @doc("The list of stop details containing stop IDs and their respective departure times.")),
    @variable(name = "routeType", type = IType.INT, doc = @doc("The type of transport associated with this trip (bus, tram, metro, etc.)."))
})
public class TransportTripSkill extends Skill {

    // Getter and setter for tripId
    @getter("tripId")
    public int getTripId(final IAgent agent) {
        return (Integer) agent.getAttribute("tripId");
    }

    @setter("tripId")
    public void setTripId(final IAgent agent, final int tripId) {
        agent.setAttribute("tripId", tripId);
    }

    // Getter and setter for routeId
    @getter("routeId")
    public String getRouteId(final IAgent agent) {
        return (String) agent.getAttribute("routeId");
    }

    @setter("routeId")
    public void setRouteId(final IAgent agent, final String routeId) {
        agent.setAttribute("routeId", routeId);
    }

    // Getter and setter for stopsInOrder
    @getter("stopsInOrder")
    public Object getStopsInOrder(final IAgent agent) {
        return agent.getAttribute("stopsInOrder");
    }

    @setter("stopsInOrder")
    public void setStopsInOrder(final IAgent agent, final Object stopsInOrder) {
        agent.setAttribute("stopsInOrder", stopsInOrder);
    }

    // Getter and setter for destination
    @getter("destination")
    public String getDestination(final IAgent agent) {
        return (String) agent.getAttribute("destination");
    }

    @setter("destination")
    public void setDestination(final IAgent agent, final String destination) {
        agent.setAttribute("destination", destination);
    }

    // Getter and setter for stopDetails
    @getter("stopDetails")
    public Object getStopDetails(final IAgent agent) {
        return agent.getAttribute("stopDetails");
    }

    @setter("stopDetails")
    public void setStopDetails(final IAgent agent, final Object stopDetails) {
        agent.setAttribute("stopDetails", stopDetails);
    }
    
 // Getter and setter for routeType
    @getter("routeType")
    public int getRouteType(final IAgent agent) {
        return (Integer) agent.getAttribute("routeType");
    }

    @setter("routeType")
    public void setRouteType(final IAgent agent, final int routeType) {
        agent.setAttribute("routeType", routeType);
    }
}
