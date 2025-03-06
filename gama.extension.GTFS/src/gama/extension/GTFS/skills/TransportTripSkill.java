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
    @variable(name = "routeType", type = IType.INT, doc = @doc("The type of transport associated with this trip (bus, tram, metro, etc.).")),
    @variable(name = "shapeId", type = IType.INT, doc = @doc("The unique indentifier of shape"))
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

    // Getter and setter for shapeId
    @getter("shapeId")
    public int getShapeId(final IAgent agent) {
        return (int) agent.getAttribute("shapeId");
    }
    
    @setter("shapeId")
    public void setShapeId(final IAgent agent, final int shapeId) {
        agent.setAttribute("shapeId", shapeId);
    }
    

    @setter("routeId")
    public void setRouteId(final IAgent agent, final String routeId) {
        agent.setAttribute("routeId", routeId);
    }
    // Getter and setter for routeId
    @getter("routeId")
    public String getRouteId(final IAgent agent) {
        return (String) agent.getAttribute("routeId");
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
