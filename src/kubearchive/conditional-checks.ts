import { createConditionsHook } from '~/feature-flags/hooks';
import { ensureConditionIsOn } from '~/feature-flags/utils';
import { commonFetch } from '~/k8s';
import { KUBEARCHIVE_PATH_PREFIX } from './const';

export const checkIfKubeArchiveIsEnabled = async () => {
  try {
    await commonFetch('/livez', { pathPrefix: KUBEARCHIVE_PATH_PREFIX });
    return true;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.log('no e2e coverage');
    return false;
  }
};

export const useIsKubeArchiveEnabled = createConditionsHook(['isKubearchiveEnabled']);

export const isKubeArchiveEnabled = ensureConditionIsOn(['isKubearchiveEnabled']);
