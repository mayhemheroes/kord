//! Helpers for training models.

// Sigmoid.

use burn::{
    tensor::{
        backend::Backend,
        Tensor
    },
    train::{
        metric::{
            state::{FormatOptions, NumericMetricState},
            Adaptor, LossInput, Metric, MetricEntry, Numeric,
        },
    },
};

use crate::ml::base::NUM_CLASSES;


#[derive(Debug, Clone)]
pub(crate) struct Sigmoid {
    scale: f32,
}

impl Sigmoid {
    /// Create the module from the given configuration.
    pub fn new(scale: f32) -> Self {
        Self { scale }
    }

    pub fn forward<B: Backend, const D: usize>(&self, input: Tensor<B, D>) -> Tensor<B, D> {
        let scaled = input.mul_scalar(self.scale);
        scaled.exp().div(&scaled.exp().add_scalar(1.0))
    }
}

// Loss function.

// #[derive(Debug, Clone, Default)]
// pub(crate) struct MeanSquareLoss<B: Backend> {
//     _b: B,
// }

// impl<B: Backend> MeanSquareLoss<B> {
//     pub fn forward(&self, outputs: &Tensor<B, 2>, targets: &Tensor<B, 2>) -> Tensor<B, 1> {
//         // Compute the mean square error loss.
//         outputs.sub(targets).powf(2.0).mean()
//     }
// }

#[derive(Debug, Clone, Default)]
pub struct BinaryCrossEntropyLoss<B: Backend> {
    _b: B,
}

impl<B: Backend> BinaryCrossEntropyLoss<B> {
    pub fn forward(&self, outputs: &Tensor<B, 2>, targets: &Tensor<B, 2>) -> Tensor<B, 1> {
        (targets.mul(&outputs.log()) + (targets.neg().add_scalar(1.0)).mul(&outputs.neg().add_scalar(1.0).log())).mean().neg()
    }
}

// Classification.

pub(crate) struct KordClassificationOutput<B: Backend> {
    pub loss: Tensor<B, 1>,
    pub output: Tensor<B, 2>,
    pub targets: Tensor<B, 2>,
}

impl<B: Backend> Adaptor<KordAccuracyInput<B>> for KordClassificationOutput<B> {
    fn adapt(&self) -> KordAccuracyInput<B> {
        KordAccuracyInput {
            outputs: self.output.clone(),
            targets: self.targets.clone(),
        }
    }
}

impl<B: Backend> Adaptor<LossInput<B>> for KordClassificationOutput<B> {
    fn adapt(&self) -> LossInput<B> {
        LossInput::new(self.loss.clone())
    }
}

// Accuracy metrics.

#[derive(Default)]
pub(crate) struct KordAccuracyMetric<B: Backend> {
    state: NumericMetricState,
    _b: B,
}

/// The [accuracy metric](AccuracyMetric) input type.
pub(crate) struct KordAccuracyInput<B: Backend> {
    outputs: Tensor<B, 2>,
    targets: Tensor<B, 2>,
}

impl<B: Backend> KordAccuracyMetric<B> {
    /// Create the metric.
    pub fn new() -> Self {
        Self::default()
    }
}

impl<B: Backend> Metric for KordAccuracyMetric<B> {
    type Input = KordAccuracyInput<B>;

    fn update(&mut self, input: &KordAccuracyInput<B>) -> MetricEntry {
        let [batch_size, _n_classes] = input.targets.dims();
        let device = B::Device::default();

        let targets = input.targets.to_device(&device);
        let outputs = input.outputs.to_device(&device);


        // let abs_targets = targets.powf(2.0f32).sqrt();
        // let delta = targets.sub(&outputs);
        // let abs_delta = delta.powf(2.0f32).sqrt();
        // let deviation = abs_delta.div(&abs_targets);

        // let error: f64 = deviation.mean().to_data().convert().value[0];

        // let accuracy = 100.0 * (1.0 - error);


        // let mse: f64 = targets.sub(&outputs).powf(2.0).mean().to_data().convert().value[0];
        // let rmse = mse.sqrt();

        // let accuracy = 100.0 * (1.0 - rmse);


        let target_round = targets.greater_equal_scalar(0.5).to_int();
        let output_round = outputs.greater_equal_scalar(0.5).to_int();

        let counts: Vec<u8> = target_round.equal(&output_round).to_int().sum_dim(1).into_data().convert().value;
        
        let accuracy = 100.0 * counts.iter().filter(|&&x| x == NUM_CLASSES as u8).count() as f64 / counts.len() as f64;


        // let loss: f64 = (targets.mul(&outputs.log()) + (targets.neg().add_scalar(1.0)).mul(&outputs.neg().add_scalar(1.0).log())).mean().neg().to_data().convert().value[0];
        // let accuracy = 100.0 * (1.0 - loss);

        self.state.update(accuracy, batch_size, FormatOptions::new("Accuracy").unit("%").precision(2))
    }

    fn clear(&mut self) {
        self.state.reset()
    }
}

impl<B: Backend> Numeric for KordAccuracyMetric<B> {
    fn value(&self) -> f64 {
        self.state.value()
    }
}
