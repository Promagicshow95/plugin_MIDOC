package gama.extension.GTFS.gaml;

import java.util.List;
import java.util.Map;

import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.population.IPopulation;
import gama.core.runtime.IScope;
import gama.core.util.IList;
import gama.gaml.statements.CreateStatement;
import gama.gaml.statements.RemoteSequence;

public class TransportTripCreator implements GTFSAgentCreator {

	@Override
	public void addInits(IScope scope, List<Map<String, Object>> inits, Integer max) {
		

	}

	@Override
	public boolean handlesCreation() {
	
		return false;
	}

	@Override
	public IList<? extends IAgent> createAgents(IScope scope, IPopulation<? extends IAgent> population,
			List<Map<String, Object>> inits, CreateStatement statement, RemoteSequence sequence) {
		
		return null;
	}

}
