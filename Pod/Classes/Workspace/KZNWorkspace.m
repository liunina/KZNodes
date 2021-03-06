//
//  Created by merowing on 29/10/14.
//
//
//

@import ObjectiveC.runtime;

#import <objc/runtime.h>
#import "KZNWorkspace.h"
#import "KZNNode.h"
#import "KZNSocket.h"
#import "KZNSocket+Internal.h"
#import "KZNNodeType.h"
#import "KZNGridView.h"

@interface KZNWorkspace () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) NSMutableArray *nodes;

@property(nonatomic, assign) NSUInteger evaluationTick;
@property(nonatomic, weak) CADisplayLink *displayLink;
@property(nonatomic, weak, readwrite) UIView *previewView;
@property(nonatomic, weak) IBOutlet UITableView *tableView;
@property(nonatomic, weak) IBOutlet KZNGridView *gridView;
@property(nonatomic, copy) NSArray *nodeTypes;
@end

@implementation KZNWorkspace

+ (instancetype)workspaceWithBounds:(CGRect)bounds
{
  KZNWorkspace *workspace = [[[UINib nibWithNibName:NSStringFromClass(self.class) bundle:[NSBundle bundleForClass:self]] instantiateWithOwner:nil options:nil] firstObject];
  workspace.bounds = bounds;
  return workspace;
}


- (id)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (self) {
    [self setup];
  }

  return self;
}

- (void)awakeFromNib
{
  [super awakeFromNib];
  self.gridView.workspace = self;
}

- (void)addNode:(KZNNode *)node
{
  node.workspace = self;
  [self.nodes addObject:node];
  [self.gridView addNode:node];
}

- (void)removeNode:(KZNNode *)node
{
  [node.inputSockets enumerateObjectsUsingBlock:^(KZNSocket *socket, NSUInteger idx, BOOL *stop) {
    [self breakConnectionFromSocket:socket.sourceSocket toSocket:socket];
  }];
  [node.outputSockets enumerateObjectsUsingBlock:^(KZNSocket *socket, NSUInteger idx, BOOL *stop) {
    [socket.connections enumerateObjectsUsingBlock:^(KZNSocket *inputSocket, BOOL *stop) {
      [self breakConnectionFromSocket:inputSocket.sourceSocket toSocket:inputSocket];
    }];
  }];

  node.workspace = nil;
  [self.nodes removeObject:self];
  [self.gridView removeNode:node];
}


- (void)setup
{
  self.nodes = [NSMutableArray new];
}

- (void)willMoveToWindow:(UIWindow *)newWindow
{
  [super willMoveToWindow:newWindow];

  if (newWindow) {
    CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(refresh:)];
    self.displayLink = displayLink;
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
  } else {
    [self.displayLink invalidate];
    self.displayLink = nil;
  }
}


- (void)refresh:(CADisplayLink *)refresh
{
  self.evaluationTick++;
  [self.nodes enumerateObjectsUsingBlock:^(KZNNode *node, NSUInteger idx, BOOL *stop) {
    if (node.type.evaluationMode == KZNEvaluationModeContinuous) {
      [node evaluateWithTick:self.evaluationTick withForwardPropagation:YES];
    }
  }];
}

- (void)pressedSocket:(KZNSocket *)socket
{
  if ([socket isKindOfClass:KZNSocket.class] && socket.socketType == KZNNodeSocketTypeInput && socket.sourceSocket) {
    [self breakConnectionFromSocket:socket.sourceSocket toSocket:socket];
  }
}

- (void)breakConnectionFromSocket:(KZNSocket *)outputSocket toSocket:(KZNSocket *)inputSocket
{
  [self.gridView clearConnectionLayerForSocket:inputSocket];
  [outputSocket removeConnectionToSocket:inputSocket];
  [self evaluate];
}

- (void)evaluate
{
  NSMutableArray *finalNodes = [NSMutableArray new];
  [self.nodes enumerateObjectsUsingBlock:^(KZNNode *node, NSUInteger idx, BOOL *stop) {
    if (!node.outputSockets.count) {
      [finalNodes addObject:node];
      return;
    }

    __block BOOL finalNode = YES;
    [node.outputSockets enumerateObjectsUsingBlock:^(KZNSocket *socket, NSUInteger idx, BOOL *stop) {
      if ([socket.connections count]) {
        finalNode = NO;
        *stop = YES;
      }
    }];

    if (finalNode) {
      [finalNodes addObject:node];
    }
  }];

  [self evaluateNodes:finalNodes];
}

- (void)evaluateNodes:(NSArray *)nodes
{
  self.evaluationTick++;
  [nodes enumerateObjectsUsingBlock:^(KZNNode *node, NSUInteger idx, BOOL *stop) {
    [self evaluateNode:node withEvaluationTick:self.evaluationTick];
  }];
}


- (NSDictionary *)evaluateNode:(KZNNode *)node withEvaluationTick:(NSUInteger)tick
{
  if (!node) {
    return @{ };
  }

  return [node evaluateWithTick:tick withForwardPropagation:NO];
}

#pragma mark - UITableView DS

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
  [tableView registerNib:[UINib nibWithNibName:@"KZNWorkspaceBlockCell" bundle:[NSBundle bundleForClass:self.class]] forCellReuseIdentifier:@"DefaultCell"];
  tableView.separatorColor = [UIColor colorWithRed:0.129 green:0.137 blue:0.141 alpha:1];

  self.nodeTypes = [KZNNodeType nodeTypes].allValues;
  return self.nodeTypes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DefaultCell" forIndexPath:indexPath];
  cell.backgroundColor = cell.textLabel.backgroundColor;
  KZNNodeType *nodeType = self.nodeTypes[indexPath.row];
  cell.textLabel.text = [[nodeType name] uppercaseString];
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
  KZNNode *node = [self.nodeTypes[indexPath.row] createNode];
  node.center = self.center;
  [self addNode:node];
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end