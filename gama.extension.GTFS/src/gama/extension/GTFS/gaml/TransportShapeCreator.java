package gama.extension.GTFS.gaml;

import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.population.IPopulation;
import gama.core.metamodel.shape.IShape;
import gama.core.runtime.IScope;
import gama.core.util.GamaListFactory;
import gama.core.util.IList;
import gama.extension.GTFS.TransportShape;
import gama.extension.GTFS.TransportStop;
import gama.gaml.statements.CreateStatement;
import gama.gaml.statements.RemoteSequence;
import gama.core.common.interfaces.IKeyword;

import java.util.List;
import java.util.Map;

public class TransportShapeCreator implements GTFSAgentCreator {
	
	private List<TransportShape> shapes;

	public TransportShapeCreator(List<TransportShape> shapes) {
		this.shapes = shapes;
	}

	public void addInits(IScope scope, List<Map<String, Object>> inits, Integer max) {
	        int limit = (max != null) ? Math.min(max, shapes.size()) : shapes.size();

	        for (int i = 0; i < limit; i++) {
	            TransportShape shape = shapes.get(i);
	            IShape polyline = shape.generateShape(scope);

	            if (polyline == null) {
	                System.err.println("[ERROR] Shape generation failed for Shape ID: " + shape.getShapeId());
	                continue;
	            }

	            // Utilisation de getAttributes(true) pour ajouter automatiquement shape
	            final Map<String, Object> map = polyline.getAttributes(true);
	            polyline.setAttribute(IKeyword.SHAPE, polyline); 
	            map.put("shapeId", shape.getShapeId());

	            inits.add(map);

	            System.out.println("[INFO] Shape Init added for Shape ID: " + shape.getShapeId());
	        }
	    }
	 
	 @Override
	    public IList<? extends IAgent> createAgents(IScope scope, IPopulation<? extends IAgent> population, List<Map<String, Object>> inits, CreateStatement statement, RemoteSequence sequence) {
	        System.out.println("[DEBUG] Before createAgents -> inits size: " + inits.size());

	        for (Map<String, Object> init : inits) {
	            System.out.println("[DEBUG] Shape in inits -> " + init.get("shape"));
	        }

	        IList<? extends IAgent> createdAgents = population.createAgents(scope, inits.size(), inits, false, true);

	        System.out.println("[DEBUG] After createAgents -> Created agents: " + createdAgents.size());

	        for (IAgent agent : createdAgents) {
	            System.out.println("[DEBUG] Agent ID: " + agent.getAttribute("shapeId") + ", Shape in geometry: " + agent.getGeometry());
	        }

	        return createdAgents;
	    }

	

}
