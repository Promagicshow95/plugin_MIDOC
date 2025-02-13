package gama.extension.GTFS.gaml;

import gama.core.common.interfaces.ICreateDelegate;
import gama.core.runtime.IScope;
import gama.core.util.GamaListFactory;
import gama.core.util.IList;
import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.population.IPopulation;
import gama.extension.GTFS.GTFS_reader;
import gama.extension.GTFS.TransportRoute;
import gama.extension.GTFS.TransportShape;
import gama.extension.GTFS.TransportStop;
import gama.extension.GTFS.TransportTrip;
import gama.gaml.expressions.IExpression;
import gama.gaml.operators.Cast;
import gama.gaml.species.ISpecies;
import gama.gaml.statements.Arguments;
import gama.gaml.statements.CreateStatement;
import gama.gaml.statements.RemoteSequence;
import gama.gaml.types.IType;
import gama.gaml.types.Types;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Classe responsable de la création des agents GTFS en délégant la création à des classes spécifiques.
 */
public class CreateAgentsFromGTFS implements ICreateDelegate {

    @Override
    public boolean handlesCreation() {
        return true;
    }

    @Override
    public boolean acceptSource(IScope scope, Object source) {
        return source instanceof GTFS_reader;
    }

    @Override
    public boolean createFrom(IScope scope, List<Map<String, Object>> inits, Integer max, Object source, Arguments init, CreateStatement statement) {
        if (!(source instanceof GTFS_reader)) {
            scope.getGui().getConsole().informConsole("Invalid source: Not a GTFS_reader", scope.getSimulation());
            return false;
        }

        GTFS_reader gtfsReader = (GTFS_reader) source;
        IExpression speciesExpr = statement.getFacet("species");
        ISpecies targetSpecies = Cast.asSpecies(scope, speciesExpr.value(scope));

        if (targetSpecies == null) {
            scope.getGui().getConsole().informConsole("No species specified", scope.getSimulation());
            return false;
        }

        IPopulation<? extends IAgent> population = scope.getSimulation().getPopulationFor(targetSpecies);
        if (population == null) {
            System.err.println("[ERROR] Population not found for species: " + targetSpecies.getName());
            return false;
        }

        // Sélection de la classe appropriée pour gérer la création des agents
        GTFSAgentCreator agentCreator = getAgentCreator(targetSpecies, gtfsReader);
        if (agentCreator == null) {
            scope.getGui().getConsole().informConsole("Unrecognized skill", scope.getSimulation());
            return false;
        }

        // Génération des initialisations
        agentCreator.addInits(scope, inits, max);
        return true;
    }

    @Override
    public IType<?> fromFacetType() {
        return Types.FILE;
    }

    @Override
    public IList<? extends IAgent> createAgents(IScope scope, IPopulation<? extends IAgent> population, List<Map<String, Object>> inits, CreateStatement statement, RemoteSequence sequence) {
        if (inits.isEmpty()) {
            System.out.println("[INFO] No agents to create.");
            return GamaListFactory.create(Types.AGENT); // ✅ Retourne une IList vide avec type AGENT
        }

        // Récupérer le type de l'agent pour sélectionner la bonne classe de création
        IExpression speciesExpr = statement.getFacet("species");
        ISpecies targetSpecies = Cast.asSpecies(scope, speciesExpr.value(scope));

        if (targetSpecies == null) {
            System.err.println("[ERROR] No species found in statement.");
            return GamaListFactory.create(Types.AGENT);
        }

        GTFSAgentCreator agentCreator = getAgentCreator(targetSpecies, null);
        if (agentCreator == null) {
            System.err.println("[ERROR] No matching GTFSAgentCreator found.");
            return GamaListFactory.create(Types.AGENT);
        }

        List<? extends IAgent> createdAgents = agentCreator.createAgents(scope, population, inits, statement, sequence);
        IList<IAgent> agentList = GamaListFactory.create(Types.AGENT);
        agentList.addAll(createdAgents); 

        return agentList;
    }



    /**
     * Sélectionne le bon gestionnaire de création d'agents en fonction du type d'espèce.
     */
    private GTFSAgentCreator getAgentCreator(ISpecies species, GTFS_reader gtfsReader) {
        if (species.implementsSkill("TransportStopSkill")) {
            return new TransportStopCreator(gtfsReader != null ? gtfsReader.getStops() : null);
        } else if (species.implementsSkill("TransportShapeSkill")) {
            return new TransportShapeCreator(gtfsReader != null ? gtfsReader.getShapes() : null);
        
        }
        return null;
    }

}
