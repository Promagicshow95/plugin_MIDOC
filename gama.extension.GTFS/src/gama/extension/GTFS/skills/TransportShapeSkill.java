package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.setter;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.shape.IShape;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;

/**
 * Skill for transport shape agents.
 */
@skill(name = "TransportShapeSkill", doc = @doc("Skill for agents representing transport shapes with a polyline representation."))
@vars({
    @variable(name = "shapeId", type = IType.INT, doc = @doc("The ID of the transport shape.")),
    @variable(name = "shape", type = IType.GEOMETRY, doc = @doc("The polyline representing the transport shape."))
})
public class TransportShapeSkill extends Skill {

    @getter("shapeId")
    public int getShapeId(final IAgent agent) {
        return (int) agent.getAttribute("shapeId");
    }

    @setter("shapeId")
    public void setShapeId(final IAgent agent, final int shapeId) {
        agent.setAttribute("shapeId", shapeId);
    }

}
