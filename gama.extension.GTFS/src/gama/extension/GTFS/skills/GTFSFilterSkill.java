package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.action;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.core.runtime.IScope;
import gama.gaml.skills.Skill;
import gama.extension.GTFSfilter.GTFSFilter;
import java.io.File;

@skill(name = "gtfs_filter")
public class GTFSFilterSkill extends Skill {

    @action(
        name = "filter_gtfs_with_osm",
        doc = @doc("Filtre les fichiers GTFS selon la bounding box de l’OSM. Le résultat final (propre et cohérent) est dans output_path. Les variables globales gtfs_path, osm_path et output_path doivent être définies.")
    )
    public Object filterGtfsWithOsm(final IScope scope) {
        try {
            // Récupère les chemins depuis les variables globales GAMA
            String gtfsRelPath = scope.getGlobalVarValue("gtfs_path").toString();
            String osmRelPath = scope.getGlobalVarValue("osm_path").toString();
            String outputRelPath = scope.getGlobalVarValue("output_path").toString();

            // Résolution des chemins absolus
            String baseFolder = scope.getModel().getDescription().getModelFolderPath();
            File gtfsAbsPath = new File(baseFolder, gtfsRelPath);
            File osmAbsPath = new File(baseFolder, osmRelPath);
            File outputAbsPath = new File(baseFolder, outputRelPath);

            // Lance le filtrage + nettoyage + validation
            GTFSFilter.filter(
                gtfsAbsPath.getAbsolutePath(),
                osmAbsPath.getAbsolutePath(),
                outputAbsPath.getAbsolutePath()
            );

            // Affiche un message de succès dans la console GAMA
            if (scope.getGui() != null) {
                scope.getGui().getConsole().informConsole(
                    "✅ GTFS filtré, nettoyé et validé : " + outputAbsPath.getAbsolutePath(),
                    scope.getSimulation()
                );
                scope.getGui().getConsole().informConsole(
                    "Voir le rapport : " + outputAbsPath.getAbsolutePath() + "/validation/report.json",
                    scope.getSimulation()
                );
            }
        } catch (Exception e) {
            if (scope.getGui() != null) {
                scope.getGui().getConsole().informConsole(
                    "❌ Error while filtering/validating GTFS: " + e.getMessage(),
                    scope.getSimulation()
                );
            }
            e.printStackTrace();
        }
        return null;
    }
}
