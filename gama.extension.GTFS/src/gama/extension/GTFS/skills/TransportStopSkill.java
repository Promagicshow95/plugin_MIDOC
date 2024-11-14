
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
 * The skill TransportStopSkill for managing individual transport stops in GAMA.
 * This skill stores attributes like stopId, stopName, latitude, and longitude for each stop.
 */
@skill(name = "TransportStopSkill", doc = @doc("Skill for agents that represent individual transport stops with attributes like stopId, stopName, latitude, and longitude."))
@vars({
    @variable(name = "stopId", type = IType.STRING, doc = @doc("The ID of the transport stop.")),
    @variable(name = "stopName", type = IType.STRING, doc = @doc("The name of the transport stop.")),
//    @variable(name = "latitude", type = IType.FLOAT, doc = @doc("The latitude of the transport stop.")),
//    @variable(name = "longitude", type = IType.FLOAT, doc = @doc("The longitude of the transport stop."))
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

//    // Getter and setter for latitude
//    @getter("latitude")
//    public double getLatitude(final IAgent agent) {
//        return (Double) agent.getAttribute("latitude");
//    }
//
//    @setter("latitude")
//    public void setLatitude(final IAgent agent, final double latitude) {
//        agent.setAttribute("latitude", latitude);
//    }
//
//    // Getter and setter for longitude
//    @getter("longitude")
//    public double getLongitude(final IAgent agent) {
//        return (Double) agent.getAttribute("longitude");
//    }
//
//    @setter("longitude")
//    public void setLongitude(final IAgent agent, final double longitude) {
//        agent.setAttribute("longitude", longitude);
//    }
}
