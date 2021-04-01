classdef InterferometerPulses < handle
    properties(SetAccess = protected, Hidden = true)
        parent
        tb
    end
    
    properties(SetAccess = protected)
        mass
        k
        recoil
    end
    
    properties
        width
        t0
        T
        dt
        Tasym
        finalphase
        braggpower
        chirp
        rfscale
    end
    
    properties(Hidden = true)
        t
        freq
        pow
        phase
    end
    
    properties(Constant, Hidden = true)
        g = 9.81;
        DEFAULT_FREQ = 110;
    end
    
    methods
        function self = InterferometerPulses(parent,atom)
            if ~isa(parent,'mogdevice')
                error('Parent must be a ''mogdevice'' object!');
            end
            self.parent = parent;
            self.tb = mogtable(self.parent,1);
            self.tb(2) = mogtable(self.parent,2);
            self.setDefaults;
            if nargin > 1
                self.setAtom(atom);
            end
        end
        
        function self = setDefaults(self)
            self.setAtom('Rb87');
            self.setLatticeFreq(384224e9);
            self.rfscale = [2.38,2.08];
            self.t0 = 500e-6;
            self.T = 1e-3;
            self.dt = 1e-6;
            self.Tasym = 0;
            self.width = 50e-6;
            self.braggpower = [0.05,0.1,0.05];
            self.finalphase = 0;
            self.chirp = 2*self.k*self.g/(2*pi);
        end
        
        function self = setAtom(self,atom)
            if strcmpi(atom,'Rb87')
                self.mass = const.mRb;
            else
                error('Atom %s not recognized',atom);
            end
        end
        
        function self = setLatticeFreq(self,f)
            self.k = 2*pi*f/const.c;
            self.recoil = const.hbar*self.k^2/(2*self.mass)/(2*pi);
        end
        
        function self = set(self,varargin)
            if mod(numel(varargin),2) ~= 0
                error('Arguments must appear as name/value pairs!');
            else
                for nn = 1:2:numel(varargin)
                    v = varargin{nn+1};
                    switch lower(varargin{nn})
                        case 't0'
                            self.t0 = v;
                        case 't'
                            self.T = v;
                        case 'dt'
                            self.dt = v;
                        case 'tasym'
                            self.Tasym = v;
                        case 'width'
                            self.width = v;
                        case {'finalphase','phase'}
                            self.finalphase = v;
                        case 'rfscale'
                            self.rfscale = v;
                        case {'power','braggpower'}
                            self.braggpower = v;
                        case 'chirp'
                            self.chirp = v;
                        otherwise
                            error('Option %s not supported!',varargin{nn});
                    end
                end
            end
        end
        
        function self = makeSinglePulse(self,P,varargin)
            %Set variables
            self.set(varargin{:});
            %Reset arrays
            self.t = [];
            self.freq = [];
            self.pow = [];
            self.phase = [];
            
            %Generate time vector
            min_t = 0;
            max_t = self.t0+5*self.width;
            self.t = (min_t:1e-6:max_t)';
            %Create series of gaussian pulses
            self.pow = P*self.gauss(self.t,self.t0,self.width);
            self.pow(:,2) = self.pow(:,1);
            
            %Set phases
            self.phase = zeros(numel(self.t),2);
            
            %Set frequencies with frequency chirp
            self.freq(:,1) = self.DEFAULT_FREQ*ones(size(self.t));
            self.freq(:,2) = self.freq(:,1) + 0.5*self.chirp*self.t/(1e6)...
                + 0.5*4*self.recoil/1e6;
            
            %Create mogtable entries
            self.makeTables;
        end
        
        function self = makePulses(self,varargin)
            %Set variables
            self.set(varargin{:});
            %Reset arrays
            self.t = [];
            self.freq = [];
            self.pow = [];
            self.phase = [];
            
            %Generate time vector
            min_t = 0;
            max_t = self.t0+2*self.T+self.Tasym+5*self.width;
            self.t = (min_t:self.dt:max_t)';
            %Create series of gaussian pulses
            self.pow = self.braggpower(1)*self.gauss(self.t,self.t0,self.width)...
                + self.braggpower(2)*self.gauss(self.t,self.t0+self.T,self.width)...
                + self.braggpower(3)*self.gauss(self.t,self.t0+2*self.T+self.Tasym,self.width);
            
            self.pow(:,2) = self.pow(:,1);
            
            %Set phases
            self.phase = zeros(numel(self.t),2);
            self.phase(:,2) = self.finalphase*(self.t > (self.t0+1.5*self.T));
            
            %Set frequencies with frequency chirp
            self.freq(:,1) = self.DEFAULT_FREQ - 0.25*self.chirp*self.t/(1e6)...
                - 0.25*4*self.recoil/1e6;
            self.freq(:,2) = self.DEFAULT_FREQ + 0.25*self.chirp*self.t/(1e6)...
                + 0.25*4*self.recoil/1e6;
            
            %Create mogtable entries
            self.makeTables;
        end
        
        function self = makeTables(self)
            for nn = 1:2
                self.tb(nn).t = self.t;
                self.tb(nn).pow = 30+10*log10(mogtable.opticalToRF(self.pow(:,nn),1,self.rfscale(nn)));
                self.tb(nn).freq = self.freq(:,nn);
                self.tb(nn).phase = self.phase(:,nn);
            end
            self.reduce;
        end
        
        function self = reduce(self)
            self.tb(1).reduce;
            self.tb(2).reduce(self.tb(1).sync);
        end
        
        function self = upload(self)
            for nn = 1:numel(self.tb)
                self.parent.cmd('mode,%d,%s',self.tb(nn).channel,self.tb(nn).MODE);
                self.parent.cmd('table,stop,%d',self.tb(nn).channel);
            end
            self.parent.cmd('table,sync,1');
            self.tb.upload;
            self.tb.arm;
        end
        
        function s = struct(self)
            s = struct('mass',self.mass,'k',self.k,'recoil',self.recoil,...
                'width',self.width,'t0',self.t0,'T',self.T,'dt',self.dt,...
                'finalphase',self.finalphase,'braggpower',self.braggpower,...
                'Tasym',self.Tasym,'rfscale',self.rfscale);
        end
        
    end
    
    methods(Static)
        function y = gauss(t,t0,w)
            y = exp(-(t-t0).^2./(w/(2*sqrt(log(2)))).^2);
        end
    end
    
    
    
end