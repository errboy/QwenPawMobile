// @ts-nocheck – project-level build script
import { appTasks, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { existsSync, readFileSync } from 'fs';
import { join } from 'path';

/**
 * Keystore paths and passwords cannot live in build-profile.json5: that file is
 * tracked, and DevEco encrypts the passwords with a key that only exists on the
 * machine that generated them (so a committed copy is both a leak and useless to
 * anyone else). They stay in the git-ignored external-signing-config.json, and
 * this plugin folds it into the build profile before the signing tasks read it.
 * `devecocli signature generate` writes the block back into build-profile.json5,
 * so after re-signing move it here again and restore the placeholders.
 */
const SIGNING_FILE = 'external-signing-config.json';

function localSigning(): any {
  return {
    pluginId: 'localSigning',
    apply(currentNode: any): void {
      // getNodeDir() hands back a NormalizedFile wrapper, not a string.
      const file = join(currentNode.getNodeDir().filePath as string, SIGNING_FILE);
      if (!existsSync(file)) {
        console.warn(`[localSigning] ${file} is missing, hap will not sign. Run 'devecocli signature generate'.`);
        return;
      }
      const context = currentNode.getContext(OhosPluginId.OHOS_APP_PLUGIN);
      const profile = context.getBuildProfileOpt();
      profile.app.signingConfigs = JSON.parse(readFileSync(file, 'utf-8')).signingConfigs;
      context.setBuildProfileOpt(profile);
    },
  };
}

export default {
  system: appTasks /* Built-in plugin of Hvigor. It cannot be modified. */,
  plugins: [localSigning()] /* Custom plugin to extend the functionality of Hvigor. */,
};
