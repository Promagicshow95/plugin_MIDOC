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
 * This skill stores attributes like tripId, routeId, serviceId, directionId, and shapeId for each trip.
 */
@skill(name = "TransportTripSkill", doc = @doc("Skill for agents that represent individual transport trips with attributes like tripId, routeId, serviceId, directionId, and shapeId."))
@vars({
    @variable(name = "tripId", type = IType.INT, doc = @doc("The ID of the transport trip.")),
    @variable(name = "routeId", type = IType.STRING, doc = @doc("The ID of the route associated with the trip.")),
    @variable(name = "serviceId", type = IType.STRING, doc = @doc("The ID of the service associated with the trip.")),
    @variable(name = "directionId", type = IType.INT, doc = @doc("The direction of the trip (e.g., 0 for one direction, 1 for the reverse).")),
    @variable(name = "shapeId", type = IType.INT, doc = @doc("The ID of the shape associated with the trip."))
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

    // Getter and setter for serviceId
    @getter("serviceId")
    public String getServiceId(final IAgent agent) {
        return (String) agent.getAttribute("serviceId");
    }

    @setter("serviceId")
    public void setServiceId(final IAgent agent, final String serviceId) {
        agent.setAttribute("serviceId", serviceId);
    }

    // Getter and setter for directionId
    @getter("directionId")
    public int getDirectionId(final IAgent agent) {
        return (Integer) agent.getAttribute("directionId");
    }

    @setter("directionId")
    public void setDirectionId(final IAgent agent, final int directionId) {
        agent.setAttribute("directionId", directionId);
    }

    // Getter and setter for shapeId
    @getter("shapeId")
    public int getShapeId(final IAgent agent) {
        return (Integer) agent.getAttribute("shapeId");
    }

    @setter("shapeId")
    public void setShapeId(final IAgent agent, final int shapeId) {
        agent.setAttribute("shapeId", shapeId);
    }
}
