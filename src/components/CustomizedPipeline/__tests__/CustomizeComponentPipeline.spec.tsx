import '@testing-library/jest-dom';
import { render } from '@testing-library/react';
import { useK8sWatchResource } from '../../../k8s';
import { ComponentKind } from '../../../types';
import CustomizeComponentPipeline from '../CustomizeComponentPipeline';

jest.mock('../../../k8s', () => ({
  useK8sWatchResource: jest.fn(() => [[], true]),
}));

jest.mock('../../../hooks/useApplicationPipelineGitHubApp', () => ({
  useApplicationPipelineGitHubApp: jest.fn(() => ({
    name: 'test-app',
    url: 'https://github.com/test-app',
  })),
}));

jest.mock('../../../utils/rbac', () => ({
  useAccessReviewForModel: jest.fn(() => [true, true]),
}));

const useK8sWatchResourceMock = useK8sWatchResource as jest.Mock;

const mockComponent = {
  metadata: {
    name: `my-component`,
    annotations: {},
  },
  spec: {
    source: {
      git: {
        url: 'https://github.com/org/test',
      },
    },
  },
} as unknown as ComponentKind;

describe('CustomizeAllPipelines', () => {
  it('should render nothing while loading', () => {
    useK8sWatchResourceMock.mockReturnValueOnce([{}, false]);
    const result = render(
      <CustomizeComponentPipeline
        name="my-component"
        namespace="test"
        modalProps={{ isOpen: true }}
      />,
    );
    expect(result.baseElement.textContent).toBe('');
  });

  it('should render modal with components table', () => {
    useK8sWatchResourceMock.mockReturnValueOnce([mockComponent, true]);
    const result = render(
      <CustomizeComponentPipeline
        name="my-component"
        namespace="test"
        modalProps={{ isOpen: true }}
      />,
    );
    expect(result.getByTestId('component-row', { exact: false })).toBeInTheDocument();
  });
});
