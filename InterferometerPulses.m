classdef InterferometerPulses < handle
    properties(SetAccess = immutable)
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
        finalphase
        pipower
        rfscale
        
        t
        freq
        pow
        phase
    end
    
    properties(Constant)
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
            if nargin > 1
                self.setAtom(atom);
            end
        end
        
        function self = setDefaults(self)
            self.setAtom('Rb87');
            self.setLatticeFreq(384224e9);
            self.rfscale = [2.5,2.2];
            self.t0 = 500e-6;
            self.T = 1e-3;
            self.dt = 0;
            self.pipower = 0.1;
            self.finalphase = 0;
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
                        case 'width'
                            self.width = v;
                        case 'finalphase'
                            self.finalphase = v;
                        case 'pipower'
                            self.pipower = v;
                        case 'rfscale'
                            self.rfscale = v;
                        otherwise
                            error('Option %s not supported!',varargin{nn});
                    end
                end
            end
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
            max_t = self.t0+2*self.T+5*self.width;
            self.t = (min_t:1e-6:max_t)';
            %Create series of gaussian pulses
            self.pow = self.pipower*(0.5*self.gauss(self.t,self.t0,self.width)...
                + self.gauss(self.t,self.t0+self.T,self.width)...
                + 0.5*self.gauss(self.t,self.t0+2*self.T+self.dt,self.width));
            
            self.pow(:,2) = self.pow(:,1);
            
            %Set phases
            self.phase = zeros(numel(self.t),2);
            self.phase(:,2) = self.finalphase*(self.t > (self.t0+1.5*self.T));
            
            %Set frequencies with frequency chirp
            self.freq(:,1) = self.DEFAULT_FREQ*ones(size(self.t));
            self.freq(:,2) = self.freq(:,1) + 0.5*2*self.k*self.g*self.t/(2*pi*1e6)...
                + 4*self.recoil/1e6;
            
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
            self.tb.reduce;
        end
        
        function self = upload(self)
            self.tb.upload;
        end
        
    end
    
    methods(Static)
        function y = gauss(t,t0,w)
            y = exp(-(t-t0).^2./(w/(2*sqrt(log(2)))).^2);
        end
    end
    
    
    
end