package gama.extension.GTFS.gaml;

import gama.core.runtime.IScope;
import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.population.IPopulation;
import gama.gaml.statements.CreateStatement;
import gama.gaml.statements.RemoteSequence;
import java.util.List;
import java.util.Map;

public interface GTFSAgentCreator {
    void addInits(IScope scope, List<Map<String, Object>> inits, Integer max);
    List<? extends IAgent> createAgents(IScope scope, IPopulation<? extends IAgent> population, List<Map<String, Object>> inits, CreateStatement statement, RemoteSequence sequence);
}
