package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.setter;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.core.metamodel.agent.IAgent;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;

/**
 * The skill TransportStopSkill for managing individual transport stops in GAMA.
 * This skill stores attributes like stopId, stopName, and location (as a GamaPoint) for each stop.
 */
@skill(name = "TransportStopSkill", doc = @doc("Skill for agents that represent individual transport stops with attributes like stopId, stopName, and location (as a GamaPoint)."))
@vars({
    @variable(name = "stopId", type = IType.STRING, doc = @doc("The ID of the transport stop.")),
    @variable(name = "stopName", type = IType.STRING, doc = @doc("The name of the transport stop.")),
    @variable(name = "routePositions", type = IType.LIST, doc = @doc("The roles of the stop, such as START or END."))
//    @variable(name = "location", type = IType.POINT, doc = @doc("The transformed location of the transport stop in the GAMA CRS, stored as a GamaPoint."))
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
    
    @getter("routePosition")
    public String getRoutePosition(final IAgent agent) {
        return (String) agent.getAttribute("routePosition");
    }
    
    @setter("routePosition")
    public void setRoutePosition(final IAgent agent, final String routePosition) {
        agent.setAttribute("routePosition", routePosition);
    }

//    // Getter and setter for location
//    @getter("location")
//    public GamaPoint getLocation(final IAgent agent) {
//        return (GamaPoint) agent.getAttribute("location");
//    }

//    @setter("location")
//    public void setLocation(final IAgent agent, final GamaPoint location) {
 //       agent.setAttribute("location", location);
//    }
}
